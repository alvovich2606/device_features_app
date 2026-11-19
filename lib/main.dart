import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DeviceFeaturesApp());
}

class DeviceFeaturesApp extends StatelessWidget {
  const DeviceFeaturesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Работа с устройством',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const DeviceFeaturesScreen(),
    );
  }
}

class DeviceFeaturesScreen extends StatefulWidget {
  const DeviceFeaturesScreen({super.key});

  @override
  State<DeviceFeaturesScreen> createState() => _DeviceFeaturesScreenState();
}

class _DeviceFeaturesScreenState extends State<DeviceFeaturesScreen> {
  static const String _keyPhotoPath = 'saved_photo_path';
  static const String _keyLatitude = 'saved_latitude';
  static const String _keyLongitude = 'saved_longitude';

  final ImagePicker _picker = ImagePicker();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  String? _photoPath;
  String _photoStatus = 'Фото ещё не выбрано';
  bool _photoPermanentlyDenied = false;

  double? _latitude;
  double? _longitude;
  String _locationStatus = 'Координаты ещё не запрашивались';
  bool _isLoadingLocation = false;
  bool _locationPermanentlyDenied = false;
  bool _locationServiceDisabled = false;

  String _notificationStatus = 'Нажмите кнопку для отправки уведомления';
  bool _notificationPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _loadSavedData();
  }

  Future<void> _initNotifications() async {
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
      );
      await _notificationsPlugin.initialize(initSettings);
    } catch (_) {
      // На платформах без поддержки плагина (например, Windows) не падаем
    }
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(_keyPhotoPath);
    final savedLat = prefs.getDouble(_keyLatitude);
    final savedLng = prefs.getDouble(_keyLongitude);

    if (!mounted) return;

    setState(() {
      if (savedPath != null && File(savedPath).existsSync()) {
        _photoPath = savedPath;
        _photoStatus = 'Фото восстановлено из памяти устройства';
      }
      if (savedLat != null && savedLng != null) {
        _latitude = savedLat;
        _longitude = savedLng;
        _locationStatus = 'Координаты восстановлены из памяти устройства';
      }
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    setState(() {
      _photoPermanentlyDenied = false;
    });

    if (source == ImageSource.camera &&
        !kIsWeb &&
        (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.camera.request();
      if (status.isPermanentlyDenied) {
        setState(() {
          _photoStatus =
              'Доступ к камере запрещён навсегда. Разрешите его в настройках приложения.';
          _photoPermanentlyDenied = true;
        });
        return;
      }
      if (!status.isGranted) {
        setState(() {
          _photoStatus = 'Пользователь отказал в доступе к камере.';
        });
        return;
      }
    }

    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );

      if (file == null) {
        setState(() {
          _photoStatus = 'Выбор фото отменён пользователем.';
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPhotoPath, file.path);

      setState(() {
        _photoPath = file.path;
        _photoStatus = source == ImageSource.camera
            ? 'Снимок сделан на камеру и сохранён'
            : 'Фото выбрано из галереи и сохранено';
      });
    } on UnimplementedError {
      setState(() {
        _photoStatus =
            'Камера не поддерживается на этой платформе. Используйте кнопку «Выбрать из галереи».';
      });
    } on MissingPluginException {
      setState(() {
        _photoStatus =
            'Функция камеры недоступна на текущей платформе. Выберите файл из галереи.';
      });
    } on PlatformException catch (e) {
      setState(() {
        _photoStatus = 'Ошибка доступа к изображению: ${e.message ?? e.code}';
      });
    } catch (e) {
      setState(() {
        _photoStatus = 'Не удалось получить фото: $e';
      });
    }
  }

  Future<void> _clearPhoto() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPhotoPath);
    setState(() {
      _photoPath = null;
      _photoStatus = 'Сохранённое фото удалено';
    });
  }

  Future<void> _detectLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationPermanentlyDenied = false;
      _locationServiceDisabled = false;
      _locationStatus = 'Проверяем службы геолокации...';
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLoadingLocation = false;
          _locationServiceDisabled = true;
          _locationStatus =
              'Служба геолокации (GPS) выключена на устройстве. Включите её в настройках.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        setState(() {
          _isLoadingLocation = false;
          _locationStatus =
              'В разрешении на геолокацию отказано. Координаты недоступны.';
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLoadingLocation = false;
          _locationPermanentlyDenied = true;
          _locationStatus =
              'Доступ к геолокации запрещён навсегда. Откройте настройки приложения.';
        });
        return;
      }

      setState(() {
        _locationStatus = 'Определяем координаты...';
      });

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyLatitude, position.latitude);
      await prefs.setDouble(_keyLongitude, position.longitude);

      setState(() {
        _isLoadingLocation = false;
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationStatus = 'Координаты успешно определены и сохранены';
      });
    } on TimeoutException {
      setState(() {
        _isLoadingLocation = false;
        _locationStatus =
            'Превышено время ожидания спутников GPS. Попробуйте ещё раз.';
      });
    } on LocationServiceDisabledException {
      setState(() {
        _isLoadingLocation = false;
        _locationServiceDisabled = true;
        _locationStatus = 'Служба геолокации отключена.';
      });
    } on PermissionDeniedException {
      setState(() {
        _isLoadingLocation = false;
        _locationStatus = 'Доступ к геолокации отклонён системой.';
      });
    } on MissingPluginException {
      setState(() {
        _isLoadingLocation = false;
        _locationStatus = 'Геолокация не поддерживается на этой платформе.';
      });
    } catch (e) {
      setState(() {
        _isLoadingLocation = false;
        _locationStatus = 'Ошибка геолокации: $e';
      });
    }
  }

  Future<void> _sendNotification() async {
    setState(() {
      _notificationPermanentlyDenied = false;
    });

    try {
      if (!kIsWeb && Platform.isAndroid) {
        var status = await Permission.notification.status;
        if (status.isDenied) {
          status = await Permission.notification.request();
        }
        if (status.isPermanentlyDenied) {
          setState(() {
            _notificationStatus =
                'Разрешение на уведомления запрещено навсегда. Включите в настройках.';
            _notificationPermanentlyDenied = true;
          });
          return;
        }
        if (!status.isGranted) {
          setState(() {
            _notificationStatus =
                'Пользователь запретил показ уведомлений.';
          });
          return;
        }
      }

      final coordsInfo = (_latitude != null && _longitude != null)
          ? 'Текущие координаты: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
          : 'Практическое задание по Flutter выполнено!';

      const androidDetails = AndroidNotificationDetails(
        'main_channel',
        'Основной канал',
        channelDescription: 'Уведомления о статусе работы с устройством',
        importance: Importance.max,
        priority: Priority.high,
      );
      const darwinDetails = DarwinNotificationDetails();
      const details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      await _notificationsPlugin.show(
        0,
        'Напоминание',
        coordsInfo,
        details,
      );

      setState(() {
        _notificationStatus = 'Локальное уведомление успешно отправлено!';
      });
    } on UnimplementedError {
      setState(() {
        _notificationStatus =
            'Системные уведомления не поддерживаются на этой платформе (доступно на Android/iOS).';
      });
    } on MissingPluginException {
      setState(() {
        _notificationStatus =
            'Плагин уведомлений недоступен на текущей платформе.';
      });
    } catch (e) {
      setState(() {
        _notificationStatus = 'Не удалось отправить уведомление: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Камера, геопозиция и уведомления'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1. Фотография (image_picker)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(_photoStatus),
                    const SizedBox(height: 12),
                    if (_photoPath != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_photoPath!),
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _pickPhoto(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Выбрать из галереи'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _pickPhoto(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Сделать фото'),
                        ),
                        if (_photoPath != null)
                          TextButton.icon(
                            onPressed: _clearPhoto,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Очистить'),
                          ),
                        if (_photoPermanentlyDenied)
                          TextButton.icon(
                            onPressed: openAppSettings,
                            icon: const Icon(Icons.settings),
                            label: const Text('Открыть настройки'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '2. Геолокация (geolocator)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(_locationStatus),
                    if (_latitude != null && _longitude != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Широта: ${_latitude!.toStringAsFixed(6)}\n'
                        'Долгота: ${_longitude!.toStringAsFixed(6)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed:
                              _isLoadingLocation ? null : _detectLocation,
                          icon: _isLoadingLocation
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.my_location),
                          label: const Text('Где я?'),
                        ),
                        if (_locationPermanentlyDenied)
                          TextButton.icon(
                            onPressed: Geolocator.openAppSettings,
                            icon: const Icon(Icons.settings),
                            label: const Text('Настройки приложения'),
                          ),
                        if (_locationServiceDisabled)
                          TextButton.icon(
                            onPressed: Geolocator.openLocationSettings,
                            icon: const Icon(Icons.location_on),
                            label: const Text('Включить GPS'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '3. Уведомления (flutter_local_notifications)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(_notificationStatus),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _sendNotification,
                          icon: const Icon(Icons.notifications_active),
                          label: const Text('Показать уведомление'),
                        ),
                        if (_notificationPermanentlyDenied)
                          TextButton.icon(
                            onPressed: openAppSettings,
                            icon: const Icon(Icons.settings),
                            label: const Text('Настройки уведомлений'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}