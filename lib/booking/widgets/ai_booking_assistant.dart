import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../models/booking_settings.dart';
import '../../models/org_public_profile.dart';
import '../../models/org_service.dart';
import '../../services/booking_api_service.dart';
import '../../services/gemini_service.dart';

/// AI rezervasyon asistanı.
/// Mod seçimi olmadan doğrudan sohbet ekranı açılır.
/// Metin girişi ve sesli konuşma aynı ekranda yan yana çalışır.
/// Danışan doğrulaması sohbet akışı içinde Gemini araçları üzerinden yapılır.
class AiBookingAssistant extends StatefulWidget {
  const AiBookingAssistant({
    super.key,
    required this.orgProfile,
    required this.services,
    required this.bookingApiService,
    required this.bookingSettings,
    required this.workingHours,
    this.aiExtraContext,
  });

  final OrgPublicProfile orgProfile;
  final List<OrgService> services;
  final BookingApiService bookingApiService;
  final BookingSettings bookingSettings;
  final WorkingHours workingHours;

  /// Yönetici tarafından tanımlanan kuruma özel talimatlar.
  final String? aiExtraContext;

  @override
  State<AiBookingAssistant> createState() => _AiBookingAssistantState();
}

class _AiBookingAssistantState extends State<AiBookingAssistant> {
  // Gemini servisi
  late final GeminiService _geminiService;

  // Mesaj listesi
  final List<AiChatMessage> _messages = [];
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  bool _isLoading = false;
  bool _started = false;

  // ── Sesli Giriş (STT) ────────────────────────────────────────────────────
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _spokenText = '';

  // ── Sesli Çıkış (Gemini TTS + audioplayers) ──────────────────────────────
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isSpeaking = false;
  bool _voiceReplyEnabled = false;
  String? _cachedApiKey;

  static const _ttsEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-2.5-pro-preview-tts:generateContent';

  @override
  void initState() {
    super.initState();
    _geminiService = GeminiService(
      orgProfile: widget.orgProfile,
      services: widget.services,
      bookingApiService: widget.bookingApiService,
      bookingSettings: widget.bookingSettings,
      workingHours: widget.workingHours,
      aiExtraContext: widget.aiExtraContext,
    );
    _initAudio();
    _initSpeech();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _speech.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ── Başlatma ────────────────────────────────────────────────────────────────

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    await _sendToGemini('Merhaba!', showUserBubble: false);
  }

  void _initAudio() {
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped && mounted) {
        setState(() => _isSpeaking = false);
      }
    });
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (err) {
          if (mounted) setState(() => _isListening = false);
        },
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') &&
              mounted &&
              _isListening) {
            _stopListeningAndSend();
          }
        },
      );
    } catch (_) {
      _speechAvailable = false;
    }
    if (mounted) setState(() {});
  }

  // ── API Anahtarı ─────────────────────────────────────────────────────────

  Future<String> _getApiKey() async {
    if (_cachedApiKey != null) return _cachedApiKey!;
    const compiled =
        String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
    if (compiled.isNotEmpty) {
      _cachedApiKey = compiled;
      return _cachedApiKey!;
    }
    try {
      if (!dotenv.isInitialized) await dotenv.load(fileName: '.env');
      _cachedApiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    } catch (_) {
      _cachedApiKey = '';
    }
    return _cachedApiKey!;
  }

  // ── Gemini TTS ───────────────────────────────────────────────────────────

  /// Ham PCM verisine WAV başlığı ekler (24kHz, 16-bit, mono).
  Uint8List _addWavHeader(Uint8List pcmBytes) {
    const sampleRate = 24000;
    const numChannels = 1;
    const bitsPerSample = 16;
    final dataSize = pcmBytes.length;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final totalSize = 36 + dataSize;

    final header = ByteData(44);
    // RIFF chunk
    header.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    header.setUint32(4, totalSize, Endian.little);
    header.setUint32(8, 0x57415645, Endian.big); // "WAVE"
    // fmt chunk
    header.setUint32(12, 0x666d7420, Endian.big); // "fmt "
    header.setUint32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    // data chunk
    header.setUint32(36, 0x64617461, Endian.big); // "data"
    header.setUint32(40, dataSize, Endian.little);

    return Uint8List.fromList([...header.buffer.asUint8List(), ...pcmBytes]);
  }

  String _truncateToWords(String text, int maxWords) {
    // Markdown işaretlerini temizle
    final clean = text
        .replaceAll(RegExp(r'\*\*|__|\*|_'), '')
        .replaceAll(RegExp(r'#+\s'), '')
        .replaceAll('`', '');
    final words = clean.split(RegExp(r'\s+'));
    if (words.length <= maxWords) return clean;
    return '${words.take(maxWords).join(' ')}...';
  }

  Future<void> _speak(String text) async {
    if (!_voiceReplyEnabled || text.isEmpty) return;
    final truncated = _truncateToWords(text, 150);
    final apiKey = await _getApiKey();
    if (apiKey.isEmpty) return;

    if (mounted) setState(() => _isSpeaking = true);
    try {
      final res = await http.post(
        Uri.parse('$_ttsEndpoint?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': truncated}
              ]
            }
          ],
          'generationConfig': {
            'responseModalities': ['AUDIO'],
            'speechConfig': {
              'voiceConfig': {
                'prebuiltVoiceConfig': {'voiceName': 'Aoede'}
              }
            }
          }
        }),
      );

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final part = json['candidates'][0]['content']['parts'][0]
            ['inlineData'] as Map<String, dynamic>;
        final mimeType = part['mimeType'] as String? ?? '';
        final bytes = base64Decode(part['data'] as String);
        final audioBytes = mimeType.contains('wav') || mimeType.contains('mp3')
            ? bytes
            : _addWavHeader(bytes);
        await _audioPlayer.play(BytesSource(audioBytes));
      } else {
        if (mounted) setState(() => _isSpeaking = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  Future<void> _stopSpeaking() async {
    await _audioPlayer.stop();
    if (mounted) setState(() => _isSpeaking = false);
  }

  // ── Gemini İletişimi ─────────────────────────────────────────────────────

  Future<void> _sendToGemini(String text,
      {bool showUserBubble = true}) async {
    if (text.trim().isEmpty || _isLoading) return;

    if (showUserBubble) {
      setState(() => _messages.add(AiChatMessage(role: 'user', text: text)));
    }

    setState(() {
      _isLoading = true;
      _messages
          .add(const AiChatMessage(role: 'model', text: '', isLoading: true));
    });
    _scrollToBottom();

    try {
      final yanit = await _geminiService.sendMessage(text);

      setState(() {
        _isLoading = false;
        _messages.removeLast();
        _messages.add(AiChatMessage(role: 'model', text: yanit));
      });

      if (_voiceReplyEnabled && yanit.isNotEmpty) {
        await _speak(yanit);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _messages.removeLast();
        _messages.add(AiChatMessage(
          role: 'model',
          text: e.toString().replaceAll('Exception: ', ''),
          isError: true,
        ));
      });
    }
    _scrollToBottom();
  }

  // ── Metin Gönderme ───────────────────────────────────────────────────────

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    await _sendToGemini(text);
  }

  // ── Sesli Giriş ─────────────────────────────────────────────────────────

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListeningAndSend();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Mikrofon erişimi sağlanamadı. Tarayıcı iznini kontrol edin.'),
        ));
      }
      return;
    }
    await _stopSpeaking();
    setState(() {
      _isListening = true;
      _spokenText = '';
    });
    await _speech.listen(
      onResult: (r) => setState(() => _spokenText = r.recognizedWords),
      localeId: 'tr_TR',
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(cancelOnError: true),
    );
  }

  Future<void> _stopListeningAndSend() async {
    if (!_isListening) return;
    await _speech.stop();
    final text = _spokenText.trim();
    setState(() {
      _isListening = false;
      _spokenText = '';
    });
    if (text.isNotEmpty) await _sendToGemini(text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // ── Üst başlık + ses toggle ──────────────────────────────────────
        _buildHeader(cs),

        // ── Mesaj listesi ─────────────────────────────────────────────────
        Expanded(
          child: _messages.isEmpty
              ? _buildEmptyState(cs)
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _ChatBubble(msg: _messages[i]),
                ),
        ),

        // ── Sesli mod göstergesi (dalga + konuşulan metin) ────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: (_isListening || _isSpeaking || _spokenText.isNotEmpty)
              ? _buildVoiceIndicator(cs)
              : const SizedBox.shrink(),
        ),

        // ── Giriş alanı ───────────────────────────────────────────────────
        _buildInputRow(cs),
      ],
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: cs.primaryContainer,
            child: Icon(Icons.smart_toy_rounded,
                size: 16, color: cs.primary),
          ),
          const SizedBox(width: 8),
          Text(
            'AI Asistan',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          // Ses kapat/aç butonu (sağ üst)
          Tooltip(
            message: _isSpeaking
                ? 'Durdur'
                : _voiceReplyEnabled
                    ? 'Sesli yanıt açık'
                    : 'Sesli yanıt kapalı',
            child: IconButton(
              icon: Icon(
                _isSpeaking
                    ? Icons.stop_circle_outlined
                    : _voiceReplyEnabled
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                size: 22,
              ),
              color: _isSpeaking
                  ? cs.error
                  : _voiceReplyEnabled
                      ? cs.primary
                      : cs.onSurfaceVariant,
              onPressed: _isSpeaking
                  ? _stopSpeaking
                  : () => setState(
                      () => _voiceReplyEnabled = !_voiceReplyEnabled),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceIndicator(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _isListening
            ? cs.errorContainer.withValues(alpha: 0.45)
            : cs.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isListening
              ? cs.error.withValues(alpha: 0.35)
              : cs.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WaveAnimation(
            color: _isListening ? cs.error : cs.primary,
            barCount: 9,
          ),
          if (_spokenText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _spokenText,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              _isListening ? 'Dinliyorum...' : 'Konuşuyor...',
              style: TextStyle(
                color: _isListening ? cs.onErrorContainer : cs.onPrimaryContainer,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primaryContainer,
            ),
            child: Icon(Icons.smart_toy_rounded,
                size: 34, color: cs.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'Asistan başlatılıyor...',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Metin alanı ───────────────────────────────────────────────
          Expanded(
            child: TextField(
              controller: _textCtrl,
              minLines: 1,
              maxLines: 5,
              enabled: !_isLoading && !_isListening,
              decoration: InputDecoration(
                hintText: _isListening ? 'Dinleniyor...' : 'Mesajınızı yazın...',
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor:
                    cs.surfaceContainerHighest.withValues(alpha: 0.6),
              ),
              onSubmitted: (_) => _sendText(),
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),

          // ── Mikrofon butonu ────────────────────────────────────────────
          _MicButton(
            isListening: _isListening,
            isDisabled: _isLoading || !_speechAvailable,
            speechAvailable: _speechAvailable,
            onTap: _toggleListening,
            cs: cs,
          ),
          const SizedBox(width: 6),

          // ── Gönder butonu ──────────────────────────────────────────────
          SizedBox(
            width: 46,
            height: 46,
            child: FilledButton(
              onPressed: (_isLoading || _isListening) ? null : _sendText,
              style: FilledButton.styleFrom(padding: EdgeInsets.zero),
              child: const Icon(Icons.send_rounded, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dalga Animasyonu ─────────────────────────────────────────────────────────

class _WaveAnimation extends StatefulWidget {
  const _WaveAnimation({required this.color, required this.barCount});
  final Color color;
  final int barCount;

  @override
  State<_WaveAnimation> createState() => _WaveAnimationState();
}

class _WaveAnimationState extends State<_WaveAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(widget.barCount, (i) {
            final phase =
                (_ctrl.value * 2 * pi) + (i / widget.barCount * 2 * pi);
            final height = 6.0 + 18.0 * ((sin(phase) + 1) / 2);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: 4,
              height: height,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ─── Mikrofon Butonu ──────────────────────────────────────────────────────────

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.isListening,
    required this.isDisabled,
    required this.speechAvailable,
    required this.onTap,
    required this.cs,
  });

  final bool isListening;
  final bool isDisabled;
  final bool speechAvailable;
  final VoidCallback onTap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final active = isListening;
    final color = active
        ? cs.error
        : isDisabled
            ? cs.onSurfaceVariant.withValues(alpha: 0.4)
            : cs.onSurfaceVariant;

    return SizedBox(
      width: 46,
      height: 46,
      child: Material(
        color: active
            ? cs.errorContainer
            : cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(23),
        child: InkWell(
          borderRadius: BorderRadius.circular(23),
          onTap: isDisabled ? null : onTap,
          child: Center(
            child: Icon(
              active ? Icons.mic_rounded : Icons.mic_none_rounded,
              color: color,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sohbet Balonu ────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.msg});
  final AiChatMessage msg;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = msg.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: cs.primary,
              child: const Icon(Icons.smart_toy_rounded,
                  size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? cs.primary
                    : msg.isError
                        ? cs.errorContainer
                        : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: msg.isLoading
                  ? const _LoadingDots()
                  : Text(
                      msg.text,
                      style: TextStyle(
                        color: isUser
                            ? cs.onPrimary
                            : msg.isError
                                ? cs.onErrorContainer
                                : cs.onSurface,
                        height: 1.45,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ─── Yükleniyor Animasyonu ────────────────────────────────────────────────────

class _LoadingDots extends StatefulWidget {
  const _LoadingDots();

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = ((_ctrl.value * 3) - i).clamp(0.0, 1.0);
          final opacity =
              (phase < 0.5 ? phase * 2 : 2 - phase * 2).clamp(0.3, 1.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
