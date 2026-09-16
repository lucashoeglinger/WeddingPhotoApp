import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:minio_new/minio.dart';

final String _secretWeddingPassword = dotenv.get("SECRET_WEDDING_PASSWORD");
final String _minioUser = dotenv.get("MINIO_ROOT_USER");
final String _minioPassword = dotenv.get("MINIO_ROOT_PASSWORD");

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  runApp(const WeddingApp());
}

class WeddingApp extends StatelessWidget {
  const WeddingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wedding Gallery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFD4AF37),
        scaffoldBackgroundColor: const Color(0xFFFAF6F0),
        fontFamily: 'Georgia',
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isUnlocked = false;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    final Uri? initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      _processIncomingUri(initialUri);
    }

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _processIncomingUri(uri);
    });
  }

  void _processIncomingUri(Uri uri) {
    // Expecting: weddingapp://auth?code=PASSWORD
    if (uri.scheme == 'weddingapp') {
      final code = uri.queryParameters['code'] ?? uri.host;
      if (code == _secretWeddingPassword) {
        _unlock();
      }
    }
  }

  void _unlock() {
    if (!_isUnlocked) {
      setState(() {
        _isUnlocked = true;
      });
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isUnlocked) {
      return const PhotoUploadPage();
    }
    return QRScannerScreen(onSuccess: _unlock);
  }
}

class QRScannerScreen extends StatefulWidget {
  final VoidCallback onSuccess;

  const QRScannerScreen({super.key, required this.onSuccess});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final TextEditingController _passcodeController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();
  bool _hasScanned = false;

  void _validateCode(String? rawInput) {
    if (_hasScanned || rawInput == null) return;

    final String cleanedInput = rawInput.trim();

    // Check if input is either the direct password OR the full deep link URL
    bool isValid = (cleanedInput == _secretWeddingPassword);
    if (!isValid && (cleanedInput.contains('weddingapp://') || cleanedInput.contains('github.io'))) {
      final Uri? uri = Uri.tryParse(cleanedInput);
      if (uri != null) {
        final code = uri.queryParameters['code'] ?? uri.host;
        isValid = (code == _secretWeddingPassword);
      }
    }

    if (isValid) {
      _hasScanned = true;
      _scannerController.stop();
      widget.onSuccess();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid code or QR link. Please try again! 🥂'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showManualEntryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFAF6F0),
        title: const Text('Enter Passcode', style: TextStyle(color: Color(0xFF8A7322))),
        content: TextField(
          controller: _passcodeController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Password, e.g. MA2026WEDDING',
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFD4AF37)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37)),
            onPressed: () {
              Navigator.pop(context);
              _validateCode(_passcodeController.text);
            },
            child: const Text('Access', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _passcodeController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Text(
                "Michael & Arianne",
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8A7322),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Scan the Table QR Code",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                "Scan the QR code at your table with your phone camera or the scanner below to unlock!",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 30),

              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      MobileScanner(
                        controller: _scannerController,
                        onDetect: (capture) {
                          final List<Barcode> barcodes = capture.barcodes;
                          for (final barcode in barcodes) {
                            if (barcode.rawValue != null) {
                              _validateCode(barcode.rawValue);
                              break;
                            }
                          }
                        },
                      ),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFD4AF37), width: 3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        width: 200,
                        height: 200,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              TextButton(
                onPressed: _showManualEntryDialog,
                child: const Text(
                  "Enter passcode manually instead",
                  style: TextStyle(
                    color: Color(0xFF8A7322),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PhotoUploadPage extends StatefulWidget {
  const PhotoUploadPage({super.key});

  @override
  State<PhotoUploadPage> createState() => _PhotoUploadPageState();
}

class _PhotoUploadPageState extends State<PhotoUploadPage> {
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  String? _statusMessage;

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFFAF6F0),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF8A7322)),
              title: const Text('Take a New Photo'),
              onTap: () {
                Navigator.pop(context);
                _processImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF8A7322)),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _processImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processImage(ImageSource source) async {
    setState(() {
      _isUploading = true;
      _statusMessage = "Accessing storage...";
    });

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        setState(() {
          _isUploading = false;
          _statusMessage = null;
        });
        return;
      }

      setState(() {
        _statusMessage = "Uploading your memory to the couple... 🥂";
      });

      final minio = Minio(
        endPoint:"chemistry-fully-pottery-oecd.trycloudflare.com",
        useSSL: true,
        accessKey: _minioUser,
        secretKey:_minioPassword
      );


      final File file = File(pickedFile.path);
      final String extension = p.extension(file.path);
      final int fileSize = await file.length();
      final fileStream = file.openRead().map((list) => Uint8List.fromList(list));
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}$extension';
    try {
        await minio.putObject(
          'weddingpictures',
          fileName,
          fileStream,
          size: fileSize,
        );
        setState(() {
          _statusMessage = "Thank you! Uploaded successfully! ❤️";
        });
    } catch (e){
        setState(() {
          _statusMessage = "Oops! Something went wrong. Try again!: $e";
        });
    }

    } catch (e) {
      if (kDebugMode) print("Upload Error: $e");
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Michael & Arianne",
                style: TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8A7322),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Welcome to our Wedding Gallery",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              const Text(
                "Capture or select moments to share with us!",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 60),

              if (_isUploading)
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _showImageSourceActionSheet(context),
                  icon: const Icon(Icons.cloud_upload, color: Colors.white),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
                    child: Text(
                      "Share a Photo",
                      style: TextStyle(fontSize: 18, color: Colors.white),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 3,
                  ),
                ),

              const SizedBox(height: 40),

              if (_statusMessage != null)
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _statusMessage!.contains("Oops") ? Colors.red : Colors.green[800],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}