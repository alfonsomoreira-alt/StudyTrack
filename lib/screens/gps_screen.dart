import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/notification_service.dart';
import '../services/plan_service.dart';
import 'notifications_screen.dart';

enum ModoRuta { auto, pie }

class GpsScreen extends StatefulWidget {
  const GpsScreen({super.key});

  @override
  State<GpsScreen> createState() => _GpsScreenState();
}

class _GpsScreenState extends State<GpsScreen> {
  static const Color bordo = Color(0xFF670810);
  static const Color blanco = Color(0xFFFFFFFF);
  static const Color coral = Color(0xFFE57373);

  bool permitirUbicacion = true;
  bool detectarProximidad = true;
  bool buscandoUbicacion = false;
  bool buscandoSugerencias = false;
  bool calculandoRuta = false;

  Position? posicionActual;

  String estadoGps = 'SIN COMPROBAR';
  String precisionGps = '--';
  String direccionActual = 'Dirección no disponible';

  bool buscandoDireccionActual = false;

  final TextEditingController direccionController = TextEditingController();

  final FocusNode direccionFocus = FocusNode();
  final MapController mapController = MapController();
  Timer? _debounce;
  static const int limiteRutasGratis = 3;
  final SharedPreferencesAsync _preferencias = SharedPreferencesAsync();
  bool _comprobandoLimite = false;

  // ============================================
  // COLORES ADAPTATIVOS DE STUDYTRACK
  // ============================================

  bool get _esOscuro => Theme.of(context).brightness == Brightness.dark;

  // Bordó en modo claro, coral en modo oscuro.
  Color get _acento => _esOscuro ? coral : bordo;

  // Texto con contraste sobre el color de acento.
  Color get _sobreAcento => _esOscuro ? Colors.black : blanco;

  Color get _superficie => Theme.of(context).colorScheme.surface;

  Color get _textoSecundario => Theme.of(context).colorScheme.onSurfaceVariant;

  AppLocalizations get _textos => AppLocalizations.of(context);

  bool get _esPortugues => Localizations.localeOf(context).languageCode == 'pt';

  String _t(String es, String pt) => _esPortugues ? pt : es;

  // Mantener los estados internos originales: solo se traduce el texto visible.
  String get _estadoVisible {
    switch (estadoGps) {
      case 'SIN COMPROBAR':
        return _t('SIN COMPROBAR', 'NÃO VERIFICADO');
      case 'BUSCANDO...':
        return _t('BUSCANDO...', 'BUSCANDO...');
      case 'GPS DESACTIVADO':
        return _t('GPS DESACTIVADO', 'GPS DESATIVADO');
      case 'PERMISO DENEGADO':
        return _t('PERMISO DENEGADO', 'PERMISSÃO NEGADA');
      case 'PERMISO BLOQUEADO':
        return _t('PERMISO BLOQUEADO', 'PERMISSÃO BLOQUEADA');
      case 'DESACTIVADO':
        return _t('DESACTIVADO', 'DESATIVADO');
      case 'ACTIVO':
        return _t('ACTIVO', 'ATIVO');
      default:
        return estadoGps;
    }
  }

  String get _direccionVisible => direccionActual == 'Dirección no disponible'
      ? _t('Dirección no disponible', 'Endereço indisponível')
      : direccionActual;

  // Traducir etiquetas de demostración sin cambiar sus identificadores.
  String _nombreLugar(String nombre) {
    switch (nombre) {
      case 'Campus Principal':
        return _t('Campus Principal', 'Câmpus principal');
      case 'Biblioteca Central':
        return _t('Biblioteca Central', 'Biblioteca central');
      case 'Laboratorio de Informática':
        return _t('Laboratorio de Informática', 'Laboratório de informática');
      default:
        return nombre;
    }
  }

  String get _idiomaNominatim =>
      _esPortugues ? 'pt-BR,pt;q=0.9,es;q=0.8' : 'es,pt-BR;q=0.9';

  // ============================================
  // NOMINATIM
  // ============================================

  DateTime? _ultimaConsultaNominatim;

  Future<void> _limitarNominatim() async {
    final anterior = _ultimaConsultaNominatim;

    if (anterior != null) {
      final espera =
          const Duration(milliseconds: 1100) -
          DateTime.now().difference(anterior);

      if (espera > Duration.zero) {
        await Future<void>.delayed(espera);
      }
    }

    _ultimaConsultaNominatim = DateTime.now();
  }

  List<Map<String, dynamic>> sugerencias = [];
  Map<String, dynamic>? destinoSeleccionado;

  List<LatLng> rutaReal = [];

  double? distanciaRutaKm;
  double? duracionRutaMin;

  ModoRuta modoRuta = ModoRuta.auto;

  final Set<String> lugaresNotificados = {};

  // Ubicaciones de demostración.
  final List<Map<String, dynamic>> ubicaciones = [
    {
      'nombre': 'Campus Principal',
      'latitud': -30.9008403,
      'longitud': -55.5354775,
    },
    {
      'nombre': 'Biblioteca Central',
      'latitud': -30.9007600,
      'longitud': -55.5353900,
    },
    {
      'nombre': 'Laboratorio de Informática',
      'latitud': -30.9009200,
      'longitud': -55.5355600,
    },
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    direccionController.dispose();
    direccionFocus.dispose();
    super.dispose();
  }

  // ============================================
  // OBTENER UBICACIÓN DEL DISPOSITIVO
  // ============================================

  Future<void> obtenerUbicacion() async {
    if (!permitirUbicacion) {
      mostrarMensaje(
        _t(
          'Activa "Permitir geolocalización" para utilizar el GPS.',
          'Ative "Permitir geolocalização" para usar o GPS.',
        ),
      );
      return;
    }

    setState(() {
      buscandoUbicacion = true;
      estadoGps = 'BUSCANDO...';
    });

    try {
      final servicioActivo = await Geolocator.isLocationServiceEnabled();

      if (!servicioActivo) {
        if (!mounted) return;

        setState(() {
          buscandoUbicacion = false;
          estadoGps = 'GPS DESACTIVADO';
          precisionGps = '--';
        });

        mostrarMensaje(
          _t(
            'Activa el servicio de ubicación del dispositivo.',
            'Ative o serviço de localização do dispositivo.',
          ),
        );
        return;
      }

      LocationPermission permiso = await Geolocator.checkPermission();

      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }

      if (permiso == LocationPermission.denied) {
        if (!mounted) return;

        setState(() {
          buscandoUbicacion = false;
          estadoGps = 'PERMISO DENEGADO';
          precisionGps = '--';
        });

        mostrarMensaje(
          _t(
            'El permiso de ubicación fue denegado.',
            'A permissão de localização foi negada.',
          ),
        );
        return;
      }

      if (permiso == LocationPermission.deniedForever) {
        if (!mounted) return;

        setState(() {
          buscandoUbicacion = false;
          estadoGps = 'PERMISO BLOQUEADO';
          precisionGps = '--';
        });

        mostrarMensaje(
          _t(
            'El permiso está bloqueado. Actívalo desde los ajustes.',
            'A permissão está bloqueada. Ative-a nas configurações do dispositivo.',
          ),
        );
        return;
      }

      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );

      if (!mounted || !permitirUbicacion) return;

      setState(() {
        posicionActual = posicion;
        buscandoUbicacion = false;
        estadoGps = 'ACTIVO';
        precisionGps = '${posicion.accuracy.toStringAsFixed(1)} m';
      });

      await verificarProximidad();
      await obtenerDireccionActual();

      try {
        mapController.move(LatLng(posicion.latitude, posicion.longitude), 16);
      } catch (_) {}

      mostrarMensaje(
        _t(
          'Posición actualizada correctamente.',
          'Localização atualizada com sucesso.',
        ),
      );
    } catch (e) {
      debugPrint('ERROR GPS: $e');

      if (!mounted) return;

      setState(() {
        buscandoUbicacion = false;
        estadoGps = 'ERROR';
        precisionGps = '--';
      });

      mostrarMensaje(
        _t(
          'No fue posible obtener la ubicación.',
          'Não foi possível obter sua localização.',
        ),
      );
    }
  }

  // ============================================
  // OBTENER DIRECCIÓN ACTUAL
  // ============================================

  Future<void> obtenerDireccionActual() async {
    if (posicionActual == null) return;

    setState(() {
      buscandoDireccionActual = true;
      direccionActual = _t('Buscando dirección...', 'Buscando endereço...');
    });

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': posicionActual!.latitude.toString(),
        'lon': posicionActual!.longitude.toString(),
        'format': 'jsonv2',
        'addressdetails': '1',
        'zoom': '18',
      });

      await _limitarNominatim();

      final respuesta = await http
          .get(
            uri,
            headers: {
              'User-Agent':
                  'StudyTrack/1.0 (+https://github.com/alfonsomoreira-alt/StudyTrack)',
              'Accept': 'application/json',
              'Accept-Language': _idiomaNominatim,
            },
          )
          .timeout(const Duration(seconds: 15));

      if (respuesta.statusCode != 200) {
        throw Exception('Nominatim reverse ${respuesta.statusCode}');
      }

      final datos = Map<String, dynamic>.from(
        jsonDecode(respuesta.body) as Map,
      );

      final address = datos['address'] is Map
          ? Map<String, dynamic>.from(datos['address'] as Map)
          : <String, dynamic>{};

      final calle =
          address['road'] ??
          address['pedestrian'] ??
          address['residential'] ??
          address['path'];

      final numero = address['house_number'];

      final ciudad =
          address['city'] ??
          address['town'] ??
          address['municipality'] ??
          address['village'];

      final estado = address['state'];

      final partes = <String>[];

      if (calle != null) {
        partes.add(
          numero == null ? calle.toString() : '${calle.toString()}, $numero',
        );
      }

      if (ciudad != null) {
        partes.add(ciudad.toString());
      }

      if (estado != null) {
        partes.add(estado.toString());
      }

      final direccion = partes.isNotEmpty
          ? partes.join(' - ')
          : (datos['display_name']?.toString() ?? 'Dirección no disponible');

      if (!mounted) return;

      setState(() {
        direccionActual = direccion;
        buscandoDireccionActual = false;
      });
    } catch (e) {
      debugPrint('ERROR DIRECCIÓN GPS: $e');

      if (!mounted) return;

      setState(() {
        direccionActual = 'Dirección no disponible';
        buscandoDireccionActual = false;
      });
    }
  }

  // ============================================
  // DETECCIÓN DE PROXIMIDAD
  // ============================================

  Future<void> verificarProximidad() async {
    if (!detectarProximidad || posicionActual == null) {
      return;
    }

    for (final lugar in ubicaciones) {
      final nombre = lugar['nombre'] as String;

      final distancia = Geolocator.distanceBetween(
        posicionActual!.latitude,
        posicionActual!.longitude,
        lugar['latitud'] as double,
        lugar['longitud'] as double,
      );

      if (distancia <= 200) {
        if (!lugaresNotificados.contains(nombre)) {
          lugaresNotificados.add(nombre);

          try {
            await NotificationService.mostrarProximidad(_nombreLugar(nombre));
          } catch (e) {
            debugPrint('Aviso de proximidad no disponible: $e');
          }
        }
      } else {
        lugaresNotificados.remove(nombre);
      }
    }
  }

  // ============================================
  // BUSCAR DESTINOS
  // ============================================

  void alCambiarBusqueda(String texto) {
    _debounce?.cancel();
    final consulta = texto.trim();
    setState(() => sugerencias = []);
    if (consulta.length < 3) return;

    // El servicio público Nominatim no permite autocompletado por pulsación.
    // La búsqueda se realiza al tocar el botón o enviar el teclado.
  }

  Future<void> buscarSugerencias(String consulta) async {
    if (consulta.trim().length < 3) return;

    setState(() {
      buscandoSugerencias = true;
    });

    try {
      final params = <String, String>{
        'q': consulta,
        'format': 'jsonv2',
        'limit': '6',
        'addressdetails': '1',
      };

      if (posicionActual != null) {
        final lat = posicionActual!.latitude;
        final lon = posicionActual!.longitude;

        params['viewbox'] =
            '${lon - 0.8},${lat + 0.8},${lon + 0.8},${lat - 0.8}';

        params['bounded'] = '0';
      }

      final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);

      await _limitarNominatim();

      final respuesta = await http
          .get(
            uri,
            headers: {
              'User-Agent':
                  'StudyTrack/1.0 (+https://github.com/alfonsomoreira-alt/StudyTrack)',
              'Accept': 'application/json',
              'Accept-Language': _idiomaNominatim,
            },
          )
          .timeout(const Duration(seconds: 15));

      if (respuesta.statusCode != 200) {
        throw Exception('Nominatim ${respuesta.statusCode}');
      }

      final datos = jsonDecode(respuesta.body);

      if (datos is! List) return;

      final resultados = datos.map<Map<String, dynamic>>((item) {
        final m = Map<String, dynamic>.from(item as Map);

        return {
          'nombre': m['display_name']?.toString() ?? consulta,
          'latitud': double.parse(m['lat'].toString()),
          'longitud': double.parse(m['lon'].toString()),
          'tipo': m['type']?.toString() ?? '',
        };
      }).toList();

      if (!mounted || direccionController.text.trim() != consulta) {
        return;
      }

      setState(() {
        sugerencias = resultados;
      });
    } catch (e) {
      debugPrint('ERROR SUGERENCIAS: $e');

      if (mounted) {
        mostrarMensaje(
          _t(
            'No se pudo consultar el buscador de destinos.',
            'Não foi possível consultar a busca de destinos.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          buscandoSugerencias = false;
        });
      }
    }
  }

  Future<void> seleccionarSugerencia(Map<String, dynamic> lugar) async {
    direccionController.text = _nombreLugar(lugar['nombre'] as String);

    direccionController.selection = TextSelection.collapsed(
      offset: direccionController.text.length,
    );

    direccionFocus.unfocus();

    setState(() {
      sugerencias = [];
      destinoSeleccionado = Map<String, dynamic>.from(lugar);
    });

    await calcularRutaReal(
      lugar['latitud'] as double,
      lugar['longitud'] as double,
    );
  }

  Future<void> buscarDireccion() async {
    if (posicionActual == null) {
      mostrarMensaje(
        _t(
          'Primero presiona ACTUALIZAR POSICIÓN para obtener tu GPS.',
          'Primeiro toque em ATUALIZAR LOCALIZAÇÃO para obter sua posição.',
        ),
      );
      return;
    }

    final consulta = direccionController.text.trim();

    if (consulta.isEmpty) {
      mostrarMensaje(
        _t('Escribe una dirección o lugar.', 'Digite um endereço ou local.'),
      );
      return;
    }

    if (sugerencias.isNotEmpty) {
      await seleccionarSugerencia(sugerencias.first);
      return;
    }

    await buscarSugerencias(consulta);

    if (!mounted) return;

    if (sugerencias.isEmpty) {
      mostrarMensaje(
        _t(
          'No encontré ese lugar. Probá con lugar, ciudad y país.',
          'Não encontrei esse local. Tente informar o local, a cidade e o país.',
        ),
      );
      return;
    }

    if (sugerencias.length == 1) {
      await seleccionarSugerencia(sugerencias.first);
    } else {
      mostrarMensaje(
        _t(
          'Elegí el destino correcto de la lista.',
          'Escolha o destino correto na lista.',
        ),
      );
    }
  }

  Future<void> seleccionarDestino(Map<String, dynamic> lugar) async {
    if (posicionActual == null) {
      mostrarMensaje(
        _t(
          'Primero actualiza tu posición GPS.',
          'Primeiro atualize sua localização pelo GPS.',
        ),
      );
      return;
    }

    setState(() {
      destinoSeleccionado = Map<String, dynamic>.from(lugar);

      direccionController.text = _nombreLugar(lugar['nombre'] as String);

      sugerencias = [];
    });

    await calcularRutaReal(
      lugar['latitud'] as double,
      lugar['longitud'] as double,
    );
  }

  Future<void> cambiarModo(ModoRuta nuevoModo) async {
    if (modoRuta == nuevoModo) return;

    setState(() {
      modoRuta = nuevoModo;
    });

    final destino = destinoSeleccionado;

    if (destino != null && posicionActual != null) {
      await calcularRutaReal(
        destino['latitud'] as double,
        destino['longitud'] as double,
      );
    }
  }

  // ============================================
  // CALCULAR RUTA REAL
  // ============================================

  Future<void> calcularRutaReal(
    double latitudDestino,
    double longitudDestino,
  ) async {
    if (posicionActual == null || calculandoRuta || _comprobandoLimite) return;
    _comprobandoLimite = true;
    final fecha = DateTime.now();
    final hoy = '${fecha.year}-${fecha.month}-${fecha.day}';
    const claveFecha = 'studytrack_gps_fecha';
    const claveContador = 'studytrack_gps_rutas';
    int usadas = 0;
    try {
      final fechaGuardada = await _preferencias.getString(claveFecha);
      usadas = fechaGuardada == hoy
          ? (await _preferencias.getInt(claveContador) ?? 0)
          : 0;
      if (!PlanService.premiumActivo && usadas >= limiteRutasGratis) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_t('🔒 Límite GPS alcanzado', '🔒 Limite de GPS atingido')),
            content: Text(_t(
              'Ya utilizaste tus 3 rutas gratuitas de hoy. Activá StudyTrack Premium para calcular rutas ilimitadas.',
              'Você já utilizou suas 3 rotas gratuitas de hoje. Ative o StudyTrack Premium para calcular rotas ilimitadas.',
            )),
            actions: [TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_t('Entendido', 'Entendi')),
            )],
          ),
        );
        return;
      }
    
    } catch (e) {
      debugPrint('No se pudo consultar el contador GPS: $e');

      if (mounted) {
        mostrarMensaje(_t(
          'No se pudo verificar el límite de rutas. Intentá de nuevo.',
          'Não foi possível verificar o limite de rotas. Tente novamente.',
        ));
      }

      return;
    } finally {
      _comprobandoLimite = false;
    }

    if (!mounted || posicionActual == null) return;

    setState(() {
      calculandoRuta = true;
      rutaReal = [];
      distanciaRutaKm = null;
      duracionRutaMin = null;
    });

    try {
      final origenLat = posicionActual!.latitude;
      final origenLon = posicionActual!.longitude;

      final base = modoRuta == ModoRuta.auto
          ? 'router.project-osrm.org'
          : 'routing.openstreetmap.de';

      final path = modoRuta == ModoRuta.auto
          ? '/route/v1/driving/$origenLon,$origenLat;$longitudDestino,$latitudDestino'
          : '/routed-foot/route/v1/driving/$origenLon,$origenLat;$longitudDestino,$latitudDestino';

      final uri = Uri.https(base, path, {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
      });

      final respuesta = await http
          .get(
            uri,
            headers: const {
              'User-Agent':
                  'StudyTrack/1.0 (+https://github.com/alfonsomoreira-alt/StudyTrack)',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (respuesta.statusCode != 200) {
        throw Exception('Ruta ${respuesta.statusCode}');
      }

      final datos = Map<String, dynamic>.from(jsonDecode(respuesta.body));

      if (datos['code'] != 'Ok') {
        throw Exception('NoRoute');
      }

      final rutas = datos['routes'] as List<dynamic>;

      if (rutas.isEmpty) {
        throw Exception('Sin rutas');
      }

      final ruta = Map<String, dynamic>.from(rutas.first as Map);

      final geometria = Map<String, dynamic>.from(ruta['geometry'] as Map);

      final coordenadas = geometria['coordinates'] as List<dynamic>;

      final puntos = coordenadas.map((c) {
        final p = c as List<dynamic>;

        return LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble());
      }).toList();

      if (!mounted) return;

      setState(() {
        rutaReal = puntos;

        distanciaRutaKm = (ruta['distance'] as num).toDouble() / 1000;

        duracionRutaMin = (ruta['duration'] as num).toDouble() / 60;

        calculandoRuta = false;
      });

      // Contabilizar únicamente rutas calculadas correctamente.
      if (!PlanService.premiumActivo) {
        try {
          await _preferencias.setString(claveFecha, hoy);
          await _preferencias.setInt(claveContador, usadas + 1);
        } catch (e) {
          debugPrint('No se pudo guardar el contador GPS: $e');
        }
      }

      if (puntos.isNotEmpty) {
        try {
          mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(puntos),
              padding: const EdgeInsets.all(45),
            ),
          );
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('ERROR RUTA: $e');

      if (!mounted) return;

      setState(() {
        calculandoRuta = false;
        rutaReal = [];
        distanciaRutaKm = null;
        duracionRutaMin = null;
      });

      mostrarMensaje(
        _t(
          'No fue posible calcular la ruta para este modo de viaje.',
          'Não foi possível calcular a rota para este meio de transporte.',
        ),
      );
    }
  }

  void limpiarRuta() {
    direccionController.clear();
    direccionFocus.unfocus();

    setState(() {
      sugerencias = [];
      destinoSeleccionado = null;
      rutaReal = [];
      distanciaRutaKm = null;
      duracionRutaMin = null;
    });

    if (posicionActual != null) {
      try {
        mapController.move(
          LatLng(posicionActual!.latitude, posicionActual!.longitude),
          16,
        );
      } catch (_) {}
    }
  }

  // ============================================
  // DISTANCIAS Y MENSAJES
  // ============================================

  double calcularDistancia(double lat, double lon) {
    if (posicionActual == null) return -1;

    return Geolocator.distanceBetween(
      posicionActual!.latitude,
      posicionActual!.longitude,
      lat,
      lon,
    );
  }

  String formatearDistancia(double distancia) {
    if (distancia < 0) {
      return _t('Actualiza tu posición', 'Atualize sua localização');
    }

    if (distancia < 1000) {
      return '${distancia.toStringAsFixed(0)} m';
    }

    return '${(distancia / 1000).toStringAsFixed(2)} km';
  }

  void mostrarMensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
      );
  }

  Color get colorEstadoGps {
    switch (estadoGps) {
      case 'ACTIVO':
        return Colors.green;

      case 'BUSCANDO...':
        return Colors.orange;

      case 'GPS DESACTIVADO':
      case 'PERMISO DENEGADO':
      case 'PERMISO BLOQUEADO':
      case 'ERROR':
        return Colors.red;

      default:
        return Colors.grey;
    }
  }

  // ============================================
  // PANTALLA PRINCIPAL
  // ============================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(
        backgroundColor: bordo,
        foregroundColor: blanco,
        elevation: 0,
        title: Text(
          _t('Ubicación y GPS', 'Localização e GPS'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: _textos.quickNotifications,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _cabecera(),

                    const SizedBox(height: 18),

                    Text(
                      _t('Servicios de ubicación', 'Serviços de localização'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _acento,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      _t(
                        'Buscá destinos y calculá rutas desde tu ubicación.',
                        'Busque destinos e calcule rotas a partir da sua localização.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _textoSecundario),
                    ),

                    const SizedBox(height: 25),

                    _permisos(),

                    const SizedBox(height: 16),

                    _estadoGps(),

                    const SizedBox(height: 16),

                    // ACTUALIZAR POSICIÓN
                    SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _acento,
                          foregroundColor: _sobreAcento,
                        ),

                        onPressed: buscandoUbicacion ? null : obtenerUbicacion,

                        icon: buscandoUbicacion
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _sobreAcento,
                                ),
                              )
                            : const Icon(Icons.my_location),

                        label: Text(
                          buscandoUbicacion
                              ? _t(
                                  'OBTENIENDO POSICIÓN...',
                                  'OBTENDO LOCALIZAÇÃO...',
                                )
                              : _t(
                                  'ACTUALIZAR POSICIÓN',
                                  'ATUALIZAR LOCALIZAÇÃO',
                                ),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                    if (posicionActual != null) ...[
                      const SizedBox(height: 22),

                      _buscador(),

                      const SizedBox(height: 22),

                      _mapa(),

                      const SizedBox(height: 14),

                      _posicionActual(),

                      if (destinoSeleccionado != null) ...[
                        const SizedBox(height: 12),
                        _infoRuta(),
                      ],

                      const SizedBox(height: 22),

                      _ubicacionesGuardadas(),
                    ],

                    const SizedBox(height: 15),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================
  // CABECERA
  // ============================================

  Widget _cabecera() => Container(
    height: 120,
    decoration: BoxDecoration(
      color: const Color(0xFF101923),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.location_on, color: Colors.blueAccent, size: 55),
        SizedBox(height: 5),
        Text(
          _t('GPS LOCATION', 'LOCALIZAÇÃO GPS'),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    ),
  );

  // ============================================
  // CONFIGURACIÓN DE PERMISOS
  // ============================================

  Widget _permisos() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _t('⚙ CONFIGURACIÓN DE PERMISOS', '⚙ CONFIGURAÇÃO DE PERMISSÕES'),
        style: TextStyle(
          color: _acento,
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),

      const SizedBox(height: 10),

      _card(
        Column(
          children: [
            SwitchListTile(
              activeThumbColor: _acento,
              title: Text(
                _t('Permitir geolocalización', 'Permitir geolocalização'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                _t(
                  'Permite que StudyTrack acceda a tu ubicación.',
                  'Permite que o StudyTrack acesse sua localização.',
                ),
              ),
              value: permitirUbicacion,
              onChanged: (v) => setState(() {
                permitirUbicacion = v;

                if (!v) {
                  posicionActual = null;
                  buscandoUbicacion = false;
                  destinoSeleccionado = null;
                  rutaReal = [];
                  sugerencias = [];
                  lugaresNotificados.clear();
                  estadoGps = 'DESACTIVADO';
                  precisionGps = '--';
                  direccionActual = 'Dirección no disponible';
                  buscandoDireccionActual = false;
                }
              }),
            ),

            const Divider(height: 1),

            SwitchListTile(
              activeThumbColor: _acento,
              title: Text(
                _t('Detección de proximidad', 'Detecção de proximidade'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                _t(
                  'Detecta cuando estás cerca de una institución.',
                  'Detecta quando você está perto de uma instituição.',
                ),
              ),
              value: detectarProximidad,
              onChanged: (v) {
                setState(() {
                  detectarProximidad = v;

                  if (!v) {
                    lugaresNotificados.clear();
                  }
                });

                if (v && posicionActual != null) {
                  verificarProximidad();
                }
              },
            ),
          ],
        ),
      ),
    ],
  );

  // ============================================
  // ESTADO DEL GPS
  // ============================================

  Widget _estadoGps() => _card(
    Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.gps_fixed, color: _acento),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('Estado del GPS', 'Status do GPS'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),

                Text(
                  _estadoVisible,
                  style: TextStyle(
                    color: colorEstadoGps,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _t('Precisión', 'Precisão'),
                style: TextStyle(color: _textoSecundario),
              ),

              Text(
                precisionGps,
                style: TextStyle(color: _acento, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    ),
    padding: EdgeInsets.zero,
  );

  // ============================================
  // BUSCADOR DE DESTINOS
  // ============================================

  Widget _buscador() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _t('BUSCAR DESTINO', 'BUSCAR DESTINO'),
        style: TextStyle(
          color: _acento,
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),

      const SizedBox(height: 10),

      _card(
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              TextField(
                controller: direccionController,
                focusNode: direccionFocus,
                textInputAction: TextInputAction.search,
                onChanged: alCambiarBusqueda,
                onSubmitted: (_) => buscarDireccion(),

                decoration: InputDecoration(
                  labelText: _t(
                    '¿A dónde quieres ir?',
                    'Para onde você quer ir?',
                  ),
                  hintText: _t(
                    'Ej: IFSul Santana do Livramento',
                    'Ex.: IFSul Santana do Livramento',
                  ),

                  prefixIcon: Icon(Icons.search, color: _acento),

                  suffixIcon: direccionController.text.isNotEmpty
                      ? IconButton(
                          onPressed: limpiarRuta,
                          icon: const Icon(Icons.clear),
                        )
                      : null,

                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              if (buscandoSugerencias)
                LinearProgressIndicator(minHeight: 2, color: _acento),

              if (sugerencias.isNotEmpty) _listaSugerencias(),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _botonModo(
                      ModoRuta.auto,
                      Icons.directions_car,
                      _t('Auto', 'Carro'),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: _botonModo(
                      ModoRuta.pie,
                      Icons.directions_walk,
                      _t('A pie', 'A pé'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _acento,
                    foregroundColor: _sobreAcento,
                  ),

                  onPressed: calculandoRuta ? null : buscarDireccion,

                  icon: calculandoRuta
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _sobreAcento,
                          ),
                        )
                      : const Icon(Icons.route),

                  label: Text(
                    calculandoRuta
                        ? _t('CALCULANDO...', 'CALCULANDO...')
                        : _t('BUSCAR RUTA', 'BUSCAR ROTA'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        padding: EdgeInsets.zero,
      ),
    ],
  );

  // ============================================
  // LISTA DE SUGERENCIAS
  // ============================================

  Widget _listaSugerencias() => Container(
    margin: const EdgeInsets.only(top: 4),

    constraints: const BoxConstraints(maxHeight: 260),

    decoration: BoxDecoration(
      color: _superficie,
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(10),
    ),

    child: ListView.separated(
      shrinkWrap: true,
      itemCount: sugerencias.length,

      separatorBuilder: (_, _) => const Divider(height: 1),

      itemBuilder: (_, i) {
        final s = sugerencias[i];

        return ListTile(
          dense: true,
          leading: Icon(Icons.location_on_outlined, color: _acento),

          title: Text(
            s['nombre'] as String,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          onTap: () => seleccionarSugerencia(s),
        );
      },
    ),
  );

  // ============================================
  // BOTONES AUTO Y A PIE
  // ============================================

  Widget _botonModo(ModoRuta modo, IconData icono, String texto) {
    final activo = modoRuta == modo;

    return OutlinedButton.icon(
      onPressed: () => cambiarModo(modo),
      icon: Icon(icono),
      label: Text(texto),

      style: OutlinedButton.styleFrom(
        foregroundColor: activo ? _sobreAcento : _acento,

        backgroundColor: activo ? _acento : _superficie,

        side: BorderSide(color: _acento),

        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  // ============================================
  // MAPA
  // ============================================

  Widget _mapa() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _t('MAPA Y RUTA', 'MAPA E ROTA'),
        style: TextStyle(
          color: _acento,
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),

      const SizedBox(height: 10),

      Container(
        height: 400,

        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),

        clipBehavior: Clip.antiAlias,

        child: Stack(
          children: [
            FlutterMap(
              mapController: mapController,

              options: MapOptions(
                initialCenter: LatLng(
                  posicionActual!.latitude,
                  posicionActual!.longitude,
                ),
                initialZoom: 16,
              ),

              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.studytrack',
                ),

                // Mantener el bordó sobre el mapa
                // claro de OpenStreetMap.
                if (rutaReal.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(points: rutaReal, strokeWidth: 6, color: bordo),
                    ],
                  ),

                MarkerLayer(
                  markers: [
                    // Ubicación actual.
                    Marker(
                      point: LatLng(
                        posicionActual!.latitude,
                        posicionActual!.longitude,
                      ),
                      width: 60,
                      height: 60,

                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: .15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                          size: 35,
                        ),
                      ),
                    ),

                    // Destino seleccionado.
                    if (destinoSeleccionado != null)
                      Marker(
                        point: LatLng(
                          destinoSeleccionado!['latitud'] as double,
                          destinoSeleccionado!['longitud'] as double,
                        ),
                        width: 60,
                        height: 60,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 50,
                        ),
                      ),

                    // Ubicaciones de prueba.
                    ...ubicaciones.map(
                      (l) => Marker(
                        point: LatLng(
                          l['latitud'] as double,
                          l['longitud'] as double,
                        ),
                        width: 48,
                        height: 48,

                        child: GestureDetector(
                          onTap: () => seleccionarDestino(l),

                          child: Icon(
                            Icons.location_on,
                            color: _acento,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (calculandoRuta)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: .12),

                  child: Center(
                    child: CircularProgressIndicator(color: _acento),
                  ),
                ),
              ),

            // Atribución de OpenStreetMap.
            Positioned(
              left: 8,
              bottom: 8,

              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),

                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .90),
                  borderRadius: BorderRadius.circular(4),
                ),

                child: const Text(
                  '© OpenStreetMap contributors',
                  style: TextStyle(fontSize: 10, color: Colors.black87),
                ),
              ),
            ),

            // Centrar mapa en la posición actual.
            Positioned(
              right: 10,
              bottom: 10,

              child: FloatingActionButton.small(
                heroTag: 'centrarGps',
                backgroundColor: blanco,
                foregroundColor: bordo,

                onPressed: () {
                  mapController.move(
                    LatLng(posicionActual!.latitude, posicionActual!.longitude),
                    16,
                  );
                },

                child: const Icon(Icons.my_location),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  // ============================================
  // INFORMACIÓN DE LA POSICIÓN ACTUAL
  // ============================================

  Widget _posicionActual() => _card(
    Padding(
      padding: const EdgeInsets.all(16),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Icon(Icons.my_location, color: _acento),

              const SizedBox(width: 8),

              Text(
                _t(
                  'Desde: tu ubicación actual',
                  'Origem: sua localização atual',
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Icon(Icons.location_on_outlined, color: _acento, size: 22),

              const SizedBox(width: 8),

              Expanded(
                child: buscandoDireccionActual
                    ? Text(
                        _t('Buscando dirección...', 'Buscando endereço...'),
                        style: TextStyle(color: _textoSecundario),
                      )
                    : Text(
                        _direccionVisible,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),

            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  '${_t('Latitud', 'Latitude')}: ${posicionActual!.latitude.toStringAsFixed(6)}',
                  style: TextStyle(fontSize: 12, color: _textoSecundario),
                ),

                const SizedBox(height: 3),

                Text(
                  '${_t('Longitud', 'Longitude')}: ${posicionActual!.longitude.toStringAsFixed(6)}',
                  style: TextStyle(fontSize: 12, color: _textoSecundario),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    padding: EdgeInsets.zero,
  );

  // ============================================
  // INFORMACIÓN DE LA RUTA
  // ============================================

  Widget _infoRuta() => Container(
    padding: const EdgeInsets.all(16),

    decoration: BoxDecoration(
      color: _acento.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _acento.withValues(alpha: .3)),
    ),

    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Icon(
          modoRuta == ModoRuta.auto
              ? Icons.directions_car
              : Icons.directions_walk,
          color: _acento,
          size: 32,
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Text(
                _t('Ruta calculada', 'Rota calculada'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _acento,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                _nombreLugar(destinoSeleccionado!['nombre'] as String),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              if (calculandoRuta)
                Text(
                  _t(
                    'Calculando ruta por las calles...',
                    'Calculando a rota pelas ruas...',
                  ),
                ),

              if (!calculandoRuta && distanciaRutaKm != null)
                Text(
                  '📏 ${_t('Distancia', 'Distância')}: ${distanciaRutaKm!.toStringAsFixed(2)} km',
                ),

              if (!calculandoRuta && duracionRutaMin != null) ...[
                const SizedBox(height: 6),

                Text(
                  '⏱️ ${_t('Tiempo estimado', 'Tempo estimado')}: ${duracionRutaMin!.ceil()} min',
                ),

                const SizedBox(height: 6),

                Text(
                  modoRuta == ModoRuta.auto
                      ? _t('🚗 Ruta en automóvil', '🚗 Rota de carro')
                      : _t('🚶 Ruta a pie', '🚶 Rota a pé'),
                ),
              ],
            ],
          ),
        ),

        IconButton(
          onPressed: limpiarRuta,
          icon: Icon(Icons.close, color: _acento),
        ),
      ],
    ),
  );

  // ============================================
  // UBICACIONES DE PRUEBA
  // ============================================

  Widget _ubicacionesGuardadas() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,

    children: [
      Text(
        _t('UBICACIONES DE PRUEBA', 'LOCAIS DE TESTE'),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),

      const SizedBox(height: 6),

      Text(
        _t(
          'Puntos de demostración; comprobá las coordenadas antes de usarlos.',
          'Pontos de demonstração; confira as coordenadas antes de usá-los.',
        ),
        style: TextStyle(color: _textoSecundario, fontSize: 13),
      ),

      const SizedBox(height: 10),

      ...ubicaciones.map((l) {
        final d = calcularDistancia(
          l['latitud'] as double,
          l['longitud'] as double,
        );

        final enRango = d >= 0 && d <= 200;

        final estado = !detectarProximidad
            ? 'DESACTIVADO'
            : enRango
            ? 'EN RANGO'
            : 'FUERA DE RANGO';

        final color = !detectarProximidad
            ? Colors.grey
            : enRango
            ? Colors.green
            : Colors.orange;

        return _tarjetaUbicacion(
          l,
          formatearDistancia(d),
          _t(
            estado,
            estado == 'DESACTIVADO'
                ? 'DESATIVADO'
                : estado == 'EN RANGO'
                ? 'DENTRO DO ALCANCE'
                : 'FORA DO ALCANCE',
          ),
          color,
        );
      }),
    ],
  );

  // ============================================
  // TARJETA DE UBICACIÓN
  // ============================================

  Widget _tarjetaUbicacion(
    Map<String, dynamic> lugar,
    String distancia,
    String estado,
    Color color,
  ) {
    final seleccionado = destinoSeleccionado?['nombre'] == lugar['nombre'];

    return InkWell(
      onTap: () => seleccionarDestino(lugar),
      borderRadius: BorderRadius.circular(10),

      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(13),

        decoration: BoxDecoration(
          color: seleccionado ? _acento.withValues(alpha: .10) : _superficie,

          borderRadius: BorderRadius.circular(10),

          border: Border.all(
            color: seleccionado ? _acento : Theme.of(context).dividerColor,
            width: seleccionado ? 2 : 1,
          ),
        ),

        child: Row(
          children: [
            Icon(
              seleccionado ? Icons.navigation : Icons.location_on_outlined,
              color: _acento,
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    _nombreLugar(lugar['nombre'] as String),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    distancia,
                    style: TextStyle(color: _textoSecundario, fontSize: 12),
                  ),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),

              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
              ),

              child: Text(
                estado,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // TARJETA REUTILIZABLE
  // ============================================

  Widget _card(Widget child, {EdgeInsets padding = EdgeInsets.zero}) =>
      Container(
        padding: padding,

        decoration: BoxDecoration(
          color: _superficie,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),

        child: child,
      );
}
