import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../l10n/app_localizations.dart';
import '../services/api_client.dart';
import '../services/api_login.dart';
import '../services/language_controller.dart';
import '../widgets/legal_consent.dart';

import 'dashboard_screen.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';


// =====================================================
// LOGIN DE STUDYTRACK
// =====================================================
//
// Inicio de sesión con Firebase y Google.
//
// Selector de idioma:
// - Español
// - Português (Brasil)
//
// La preferencia se comparte con toda la aplicación
// mediante el languageController.
//
// El Login conserva su diseño claro original.
//
// =====================================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // =====================================================
  // ESTADO DEL LOGIN
  // =====================================================

  bool ocultarContrasena = true;
  bool cargando = false;

  // =====================================================
  // COLORES ORIGINALES
  // =====================================================

  static const Color bordo = Color(0xFF670810);
  static const Color negro = Color(0xFF222222);
  static const Color gris = Color(0xFF666666);
  static const Color grisIconos = Color(0xFF5B5050);

  // =====================================================
  // CONTROLADORES
  // =====================================================

  final TextEditingController correoController = TextEditingController();

  final TextEditingController contrasenaController = TextEditingController();

  // Google Sign-In se inicializa una sola vez.
  static Future<void>? _inicializacionGoogle;

  // =====================================================
  // TRADUCCIONES
  // =====================================================

  // Los textos comunes vienen de AppLocalizations.
  // Para mensajes específicos usamos _t().
  //
  // El idioma se obtiene del MaterialApp principal.

  String _t(String es, String pt) {
    final idioma = Localizations.localeOf(context).languageCode;

    return idioma == 'pt' ? pt : es;
  }

  // =====================================================
  // CAMBIAR IDIOMA
  // =====================================================

  Future<void> _cambiarIdioma(String idioma) async {
    if (idioma == languageController.languageCode) {
      return;
    }

    try {
      // Este controlador es el mismo que usa Perfil.
      // Guarda la preferencia para toda StudyTrack.

      await languageController.setLanguage(idioma);

      if (!mounted) return;

      setState(() {});
    } catch (error) {
      debugPrint('Error cambiando el idioma: $error');

      if (!mounted) return;

      mostrarMensaje(
        _t(
          'No se pudo cambiar el idioma.',
          'Não foi possível alterar o idioma.',
        ),
      );
    }
  }

  // =====================================================
  // MENÚ DESPLEGABLE DE IDIOMA
  // =====================================================

  Widget _selectorIdioma() {
    final textos = AppLocalizations.of(context);

    final idiomaActual = languageController.languageCode;

    return Align(
      alignment: Alignment.centerRight,

      child: PopupMenuButton<String>(
        tooltip: textos.profileLanguage,

        position: PopupMenuPosition.under,

        constraints: const BoxConstraints(minWidth: 215),

        // El cambio se guarda automáticamente.
        onSelected: _cambiarIdioma,

        // ==========================================
        // OPCIONES DE IDIOMA
        // ==========================================
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: 'es',

            child: Row(
              children: [
                const Text('🇺🇾', style: TextStyle(fontSize: 20)),

                const SizedBox(width: 10),

                const Expanded(child: Text('Español')),

                if (idiomaActual == 'es')
                  const Icon(Icons.check, color: bordo, size: 19),
              ],
            ),
          ),

          PopupMenuItem<String>(
            value: 'pt_BR',

            child: Row(
              children: [
                const Text('🇧🇷', style: TextStyle(fontSize: 20)),

                const SizedBox(width: 10),

                const Expanded(child: Text('Português (Brasil)')),

                if (idiomaActual == 'pt_BR')
                  const Icon(Icons.check, color: bordo, size: 19),
              ],
            ),
          ),
        ],

        // ==========================================
        // BOTÓN VISIBLE EN LOGIN
        // ==========================================
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(10),

            border: Border.all(color: Colors.black12),
          ),

          child: Row(
            mainAxisSize: MainAxisSize.min,

            children: [
              const Icon(Icons.language_outlined, color: bordo, size: 21),

              const SizedBox(width: 7),

              Text(
                textos.profileLanguage,

                style: const TextStyle(
                  color: negro,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),

              const SizedBox(width: 4),

              const Icon(
                Icons.keyboard_arrow_down,
                color: grisIconos,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // MOSTRAR MENSAJES
  // =====================================================

  void mostrarMensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje), backgroundColor: bordo));
  }

  // =====================================================
  // NAVEGACIÓN AL DASHBOARD
  // =====================================================

  void abrirDashboard() {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const DashboardScreen()),
    );
  }

  // =====================================================
  // INICIAR SESIÓN CON CORREO Y CONTRASEÑA
  // =====================================================

  Future<void> iniciarSesion() async {
    if (cargando) return;

    final correo = correoController.text.trim();

    final contrasena = contrasenaController.text;

    // ==========================================
    // VALIDAR CAMPOS
    // ==========================================

    if (correo.isEmpty || contrasena.isEmpty) {
      mostrarMensaje(
        _t(
          'Completa el correo y la contraseña.',
          'Preencha o e-mail e a senha.',
        ),
      );

      return;
    }

    setState(() {
      cargando = true;
    });

    try {
      // ========================================
      // AUTENTICACIÓN CON FIREBASE
      // ========================================

      final credencial = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: correo,
        password: contrasena,
      );

      await credencial.user?.reload();

      final usuario = FirebaseAuth.instance.currentUser;

      if (!mounted) return;

      if (usuario == null) {
        mostrarMensaje(
          _t(
            'No se pudo obtener el usuario.',
            'Não foi possível obter os dados '
                'do usuário.',
          ),
        );

        return;
      }

      // ========================================
      // VERIFICACIÓN DE GMAIL
      // ========================================

      // Conservar el comportamiento original:
      // verificar el correo para cuentas Gmail.

      final esGmail = (usuario.email ?? '').toLowerCase().endsWith(
        '@gmail.com',
      );

      if (esGmail && !usuario.emailVerified) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        mostrarMensaje(
          _t(
            'Primero tenés que verificar tu Gmail. '
                'Revisá tu correo de verificación.',
            'Primeiro você precisa verificar '
                'seu Gmail. Confira o e-mail '
                'de verificação.',
          ),
        );

        return;
      }

      // ========================================
      // ACCEDER A STUDYTRACK
      // ========================================

      if (!await connectApi(context)) return;
      abrirDashboard();
    } on ApiException catch (error) {
      if (!mounted) return;
      mostrarMensaje(error.message);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      String mensaje = _t(
        'No se pudo iniciar sesión.',
        'Não foi possível entrar na sua conta.',
      );

      // ========================================
      // ERRORES DE FIREBASE TRADUCIDOS
      // ========================================

      if (error.code == 'user-not-found') {
        mensaje = _t(
          'No existe una cuenta con ese correo.',
          'Não existe uma conta com esse e-mail.',
        );
      } else if (error.code == 'wrong-password' ||
          error.code == 'invalid-credential') {
        mensaje = _t(
          'Correo o contraseña incorrectos.',
          'E-mail ou senha incorretos.',
        );
      } else if (error.code == 'invalid-email') {
        mensaje = _t(
          'El correo electrónico no es válido.',
          'O endereço de e-mail não é válido.',
        );
      } else if (error.code == 'network-request-failed') {
        mensaje = _t(
          'Revisá tu conexión a Internet.',
          'Verifique sua conexão com a Internet.',
        );
      } else if (error.code == 'too-many-requests') {
        mensaje = _t(
          'Demasiados intentos. '
              'Probá nuevamente más tarde.',
          'Muitas tentativas. '
              'Tente novamente mais tarde.',
        );
      } else if (error.code == 'user-disabled') {
        mensaje = _t(
          'Esta cuenta está deshabilitada.',
          'Esta conta está desativada.',
        );
      }

      mostrarMensaje(mensaje);
    } catch (error) {
      debugPrint('Error en inicio de sesión: $error');

      if (!mounted) return;

      mostrarMensaje(
        _t('Ocurrió un error inesperado.', 'Ocorreu um erro inesperado.'),
      );
    } finally {
      if (mounted) {
        setState(() {
          cargando = false;
        });
      }
    }
  }

  // =====================================================
  // INICIAR SESIÓN CON GOOGLE
  // ANDROID Y WEB
  // =====================================================

  Future<void> iniciarSesionConGoogle() async {
    if (cargando) return;

    setState(() {
      cargando = true;
    });

    try {
      final acceptance = await requestLegalAcceptance(context);
      if (acceptance == null || !mounted) return;
      // ========================================
      // GOOGLE EN NAVEGADORES
      // ========================================

      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();

        await FirebaseAuth.instance.signInWithPopup(googleProvider);

        // ========================================
        // GOOGLE EN ANDROID
        // ========================================
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        // Inicializar Google Sign-In una sola vez.

        _inicializacionGoogle ??= GoogleSignIn.instance.initialize();

        await _inicializacionGoogle;

        // Mostrar selector de cuentas.

        final googleUser = await GoogleSignIn.instance.authenticate();

        // Obtener token de identificación.

        final googleAuth = googleUser.authentication;

        final idToken = googleAuth.idToken;

        if (idToken == null) {
          throw StateError(
            'Google no devolvió un token '
            'de identificación.',
          );
        }

        // Crear credenciales de Firebase.

        final credencial = GoogleAuthProvider.credential(idToken: idToken);

        // Iniciar sesión en Firebase.

        await FirebaseAuth.instance.signInWithCredential(credencial);
      } else {
        if (!mounted) return;

        mostrarMensaje(
          _t(
            'Inicio con Google disponible '
                'en Android y Web.',
            'Login com Google disponível '
                'no Android e na Web.',
          ),
        );

        return;
      }

      if (!mounted) return;

      final usuario = FirebaseAuth.instance.currentUser;

      if (usuario == null) {
        mostrarMensaje(
          _t(
            'Google no pudo completar '
                'el inicio de sesión.',
            'O Google não conseguiu concluir '
                'o login.',
          ),
        );

        return;
      }

      // ========================================
      // ENTRAR AL DASHBOARD
      // ========================================

      if (!await connectApi(context, acceptance: acceptance)) return;
      abrirDashboard();
    } on ApiException catch (error) {
      if (!mounted) return;
      mostrarMensaje(error.message);
    } on GoogleSignInException catch (error) {
      debugPrint(
        'Error de Google Sign-In: '
        '${error.code} - ${error.description}',
      );

      if (!mounted) return;

      if (error.code == GoogleSignInExceptionCode.canceled) {
        mostrarMensaje(
          _t(
            'No se completó la selección de Google. '
                'Si no cancelaste, revisaremos '
                'la configuración.',
            'A seleção da conta Google '
                'não foi concluída. '
                'Se você não cancelou, será '
                'necessário revisar a configuração.',
          ),
        );
      } else {
        mostrarMensaje(
          _t(
            'Error de Google Sign-In: ${error.code}',
            'Erro no login com Google: ${error.code}',
          ),
        );
      }
    } on FirebaseAuthException catch (error) {
      debugPrint(
        'Error de Firebase Google: '
        '${error.code} - ${error.message}',
      );

      if (!mounted) return;

      mostrarMensaje(
        _t(
          'Error de Firebase: ${error.code}',
          'Erro do Firebase: ${error.code}',
        ),
      );
    } catch (error) {
      debugPrint('Error inesperado de Google: $error');

      if (!mounted) return;

      mostrarMensaje(
        _t(
          'No se pudo iniciar sesión con Google. '
              'Revisá la terminal.',
          'Não foi possível entrar com o Google. '
              'Verifique o terminal.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          cargando = false;
        });
      }
    }
  }

  // =====================================================
  // ABRIR REGISTRO
  // =====================================================

  void abrirRegistro() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterScreen()),
    );
  }

  // =====================================================
  // ABRIR RECUPERACIÓN DE CONTRASEÑA
  // =====================================================

  void abrirRecuperacion() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ForgotPasswordScreen(initialEmail: correoController.text.trim()),
      ),
    );
  }

  // =====================================================
  // LIBERAR CONTROLADORES
  // =====================================================

  @override
  void dispose() {
    correoController.dispose();
    contrasenaController.dispose();

    super.dispose();
  }

  // =====================================================
  // DISEÑO DEL LOGIN
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final textos = AppLocalizations.of(context);

    // El Login mantiene un tema claro propio,
    // sin importar el tema global de StudyTrack.

    final temaLogin = ThemeData.light(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: bordo,
        brightness: Brightness.light,
      ),

      scaffoldBackgroundColor: Colors.white,

      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: bordo,
        selectionHandleColor: bordo,
      ),
    );

    return Theme(
      data: temaLogin,

      child: Scaffold(
        backgroundColor: Colors.white,

        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,

              children: [
                // ====================================
                // SELECTOR DE IDIOMA
                // ====================================

                _selectorIdioma(),

                const SizedBox(height: 12),

                // ====================================
                // LOGO ORIGINAL
                // ====================================
                Center(
                  child: Image.asset(
                    'assets/images/logo_studytrack.png',
                    width: 200,
                    height: 160,
                    fit: BoxFit.contain,
                  ),
                ),

                const SizedBox(height: 5),

                // ====================================
                // LEMA
                // ====================================
                Center(
                  child: Text(
                    textos.appSlogan,

                    style: const TextStyle(fontSize: 16, color: Colors.black54),

                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 40),

                // ====================================
                // CORREO ELECTRÓNICO
                // ====================================
                Text(
                  textos.authEmail,

                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: negro,
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: correoController,

                  keyboardType: TextInputType.emailAddress,

                  style: const TextStyle(color: negro, fontSize: 16),

                  cursorColor: bordo,

                  decoration: InputDecoration(
                    hintText: _t('ejemplo@correo.com', 'exemplo@email.com'),

                    hintStyle: const TextStyle(color: gris),

                    filled: true,
                    fillColor: Colors.white,

                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: grisIconos,
                    ),

                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),

                      borderSide: const BorderSide(color: bordo, width: 2),
                    ),

                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),

                      borderSide: const BorderSide(color: Colors.black26),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ====================================
                // CONTRASEÑA
                // ====================================
                Text(
                  textos.authPassword,

                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: negro,
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: contrasenaController,

                  obscureText: ocultarContrasena,

                  style: const TextStyle(color: negro, fontSize: 16),

                  cursorColor: bordo,

                  decoration: InputDecoration(
                    hintText: _t('Ingresa tu contraseña', 'Digite sua senha'),

                    hintStyle: const TextStyle(color: gris),

                    filled: true,
                    fillColor: Colors.white,

                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: grisIconos,
                    ),

                    // Mostrar u ocultar contraseña.
                    suffixIcon: IconButton(
                      tooltip: ocultarContrasena
                          ? _t('Mostrar contraseña', 'Mostrar senha')
                          : _t('Ocultar contraseña', 'Ocultar senha'),

                      icon: Icon(
                        ocultarContrasena
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,

                        color: grisIconos,
                      ),

                      onPressed: () {
                        setState(() {
                          ocultarContrasena = !ocultarContrasena;
                        });
                      },
                    ),

                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),

                      borderSide: const BorderSide(color: bordo, width: 2),
                    ),

                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),

                      borderSide: const BorderSide(color: Colors.black26),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ====================================
                // RECUPERAR CONTRASEÑA
                // ====================================
                Align(
                  alignment: Alignment.centerRight,

                  child: TextButton(
                    onPressed: cargando ? null : abrirRecuperacion,

                    child: Text(
                      textos.authForgotPassword,

                      style: const TextStyle(
                        color: bordo,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ====================================
                // BOTÓN INICIAR SESIÓN
                // ====================================
                SizedBox(
                  height: 52,

                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: bordo,
                      foregroundColor: Colors.white,

                      elevation: 0,

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),

                    onPressed: cargando ? null : iniciarSesion,

                    child: cargando
                        ? const SizedBox(
                            width: 22,
                            height: 22,

                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            textos.authLogin.toUpperCase(),

                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 24),

                // ====================================
                // SEPARADOR
                // ====================================
                Row(
                  children: [
                    const Expanded(child: Divider(color: Colors.black26)),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),

                      child: Text(
                        _t('O CONTINÚA CON', 'OU CONTINUE COM'),

                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    const Expanded(child: Divider(color: Colors.black26)),
                  ],
                ),

                const SizedBox(height: 20),

                // ====================================
                // INICIAR SESIÓN CON GOOGLE
                // ====================================
                SizedBox(
                  height: 52,

                  child: OutlinedButton.icon(
                    onPressed: cargando ? null : iniciarSesionConGoogle,

                    icon: const Icon(Icons.account_circle, size: 24),

                    label: Text(
                      _t('Continuar con Google', 'Continuar com Google'),

                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,

                      foregroundColor: Colors.black87,

                      side: const BorderSide(color: Colors.black26),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // ====================================
                // REGISTRARSE
                // ====================================
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,

                  children: [
                    Text(
                      _t(
                        '¿No tienes una cuenta? ',
                        'Ainda não tem uma conta? ',
                      ),

                      style: const TextStyle(color: Colors.black54),
                    ),

                    GestureDetector(
                      onTap: cargando ? null : abrirRegistro,

                      child: Text(
                        _t('Regístrate', 'Cadastre-se'),

                        style: const TextStyle(
                          color: bordo,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
