import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import '../l10n/app_localizations.dart';
import '../services/app_data.dart';
import '../services/api_client.dart';
import '../services/language_controller.dart';
import '../services/studytrack_repository.dart';
import '../theme_controller.dart';
import '../widgets/delete_account_dialog.dart';

import 'login_screen.dart';
import 'paywall_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Bordó institucional: siempre en la barra superior.
  static const Color bordo = Color(0xFF670810);

  // Color de acento: bordó en modo claro, coral en modo oscuro.
  Color _colorAcento(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    return esOscuro ? const Color(0xFFE57373) : bordo;
  }

  // Fondo tenue para los iconos y el avatar.
  Color _fondoIcono(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    return esOscuro
        ? const Color(0xFFE57373).withValues(alpha: 0.16)
        : const Color(0xFFF4E9EB);
  }

  final SharedPreferencesAsync _preferencias = SharedPreferencesAsync();

  final ImagePicker _selectorImagen = ImagePicker();

  StudyTrackRepository? _repositorio;

  Stream<AppDocument>? _perfilStream;

  bool _mostrarCorreo = true;
  bool _letraGrande = false;
  bool _cargando = false;

  User? get _usuario => FirebaseAuth.instance.currentUser;

  AppLocalizations get _textos => AppLocalizations.of(context);

  String _t(String es, String pt) {
    return languageController.locale.languageCode == 'pt' ? pt : es;
  }

  String _clave(String nombre) {
    return 'studytrack_${_usuario?.uid ?? 'anonimo'}_$nombre';
  }

  String get _nombreUsuario {
    final user = _usuario;

    if (user == null) {
      return _t('Estudiante', 'Estudante');
    }

    final nombre = user.displayName?.trim();

    if (nombre != null && nombre.isNotEmpty) {
      return nombre;
    }

    final correo = user.email;

    if (correo != null && correo.contains('@')) {
      return correo.split('@').first;
    }

    return _t('Estudiante', 'Estudante');
  }

  String get _proveedorCuenta {
    final proveedores =
        _usuario?.providerData
            .map((proveedor) => proveedor.providerId)
            .toList() ??
        [];

    final google = proveedores.contains('google.com');
    final correo = proveedores.contains('password');

    if (google && correo) {
      return _t('Google y correo electrónico', 'Google e e-mail');
    }

    if (google) {
      return _t('Cuenta de Google', 'Conta do Google');
    }

    return _t('Correo y contraseña', 'E-mail e senha');
  }

  @override
  void initState() {
    super.initState();

    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null) {
      _repositorio = StudyTrackRepository(uid);
      _perfilStream = _repositorio!.escucharUsuario;

      _migrarDatosAcademicos();
    }

    _cargarPreferencias();
  }

  // =====================================================
  // PREFERENCIAS LOCALES
  // =====================================================

  Future<void> _cargarPreferencias() async {
    try {
      final correo = await _preferencias.getBool(_clave('mostrar_correo'));

      final texto = await _preferencias.getBool(_clave('letra_grande'));

      if (!mounted) return;

      setState(() {
        _mostrarCorreo = correo ?? true;
        _letraGrande = texto ?? false;
      });
    } catch (error) {
      debugPrint('Error cargando preferencias: $error');
    }
  }

  // Recuperar datos guardados por la versión antigua.
  // Completa la información del perfil que aún esté vacía.
  Future<void> _migrarDatosAcademicos() async {
    final repositorio = _repositorio;

    if (repositorio == null) return;

    try {
      final documento = await repositorio.usuario.get();
      final datos = documento.data() ?? <String, dynamic>{};

      final anteriores = <String, String?>{
        'institucion': await _preferencias.getString(_clave('institucion')),
        'carrera': await _preferencias.getString(_clave('carrera')),
        'semestre': await _preferencias.getString(_clave('semestre')),
        'metaAcademica': await _preferencias.getString(
          _clave('meta_academica'),
        ),
      };

      final cambios = <String, dynamic>{};

      for (final entrada in anteriores.entries) {
        final valorAnterior = entrada.value?.trim() ?? '';

        final valorActual = datos[entrada.key]?.toString().trim() ?? '';

        if (valorActual.isEmpty && valorAnterior.isNotEmpty) {
          cambios[entrada.key] = valorAnterior;
        }
      }

      if (cambios.isNotEmpty) {
        await repositorio.usuario.set(cambios, merge: true);
      }
    } catch (error) {
      debugPrint('No se pudieron migrar los datos: $error');
    }
  }

  void _mensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _informacion(String titulo, String contenido) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(titulo),
        content: SingleChildScrollView(child: Text(contenido)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_textos.commonClose),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // EDITAR NOMBRE
  // =====================================================

  Future<void> _editarNombre() async {
    final user = _usuario;

    if (user == null || _cargando) return;

    final formulario = GlobalKey<FormState>();
    String nombreNuevo = _nombreUsuario;

    final resultado = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Editar nombre', 'Editar nome')),
        content: SizedBox(
          width: 380,
          child: Form(
            key: formulario,
            child: TextFormField(
              initialValue: nombreNuevo,
              autofocus: true,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: _textos.authFullName,
                prefixIcon: const Icon(Icons.person_outline),
              ),
              onChanged: (valor) {
                nombreNuevo = valor;
              },
              validator: (valor) {
                if (valor == null || valor.trim().length < 3) {
                  return _t(
                    'Ingresá al menos 3 caracteres.',
                    'Digite pelo menos 3 caracteres.',
                  );
                }
                return null;
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: Text(_textos.commonCancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (formulario.currentState!.validate()) {
                Navigator.pop(dialogContext, nombreNuevo.trim());
              }
            },
            child: Text(_textos.commonSave),
          ),
        ],
      ),
    );

    if (resultado == null || resultado == user.displayName?.trim()) {
      return;
    }

    setState(() => _cargando = true);

    try {
      await _repositorio!.usuario.set({'nombre': resultado}, merge: true);
      await user.updateDisplayName(resultado);
      await user.reload();

      if (!mounted) return;

      setState(() {});
      _mensaje(_textos.profileSaveSuccess);
    } on ApiException catch (error) {
      _mensaje(error.message);
    } catch (error) {
      _mensaje(
        _t(
          'No se pudo actualizar el nombre.',
          'Não foi possível atualizar o nome.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  // =====================================================
  // FOTO PERSONALIZADA (NO DEPENDE DE GOOGLE)
  // =====================================================

  Future<void> _cambiarFoto() async {
    if (_cargando || _repositorio == null) return;

    try {
      // Elegir imagen de la galería.
      final archivo = await _selectorImagen.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      // El usuario canceló la selección.
      if (archivo == null) return;

      // Limitar imágenes originales demasiado grandes.
      final tamanio = await archivo.length();

      if (tamanio > 8 * 1024 * 1024) {
        _mensaje(
          _t(
            'Elegí una imagen de menos de 8 MB.',
            'Escolha uma imagem com menos de 8 MB.',
          ),
        );
        return;
      }

      if (!mounted) return;
      setState(() => _cargando = true);

      final originales = await archivo.readAsBytes();

      // Convertir a una miniatura JPEG para el perfil.
      final imagen = img.decodeImage(originales);

      if (imagen == null) {
        throw const FormatException('Formato de imagen no compatible.');
      }

      img.Image reducida = imagen;

      if (imagen.width > 360 || imagen.height > 360) {
        reducida = imagen.width >= imagen.height
            ? img.copyResize(imagen, width: 360)
            : img.copyResize(imagen, height: 360);
      }

      var fotoComprimida = Uint8List.fromList(
        img.encodeJpg(reducida, quality: 72),
      );

      // Segunda compresión, si hace falta.
      if (fotoComprimida.length > 150 * 1024) {
        final masPequenia = img.copyResize(reducida, width: 240);

        fotoComprimida = Uint8List.fromList(
          img.encodeJpg(masPequenia, quality: 55),
        );
      }

      if (fotoComprimida.length > 150 * 1024) {
        throw const FormatException('La imagen sigue siendo demasiado grande.');
      }

      // Guardar la foto en el perfil mediante la API.
      await _repositorio!.usuario.set({
        'fotoPerfilBytes': AppBlob(fotoComprimida),
        'fotoPerfilActualizada': AppFieldValue.serverTimestamp(),
      }, merge: true);

      _mensaje(_t('Foto de perfil actualizada.', 'Foto de perfil atualizada.'));
    } catch (error) {
      debugPrint('Error cambiando foto: $error');

      _mensaje(
        _t(
          'No se pudo guardar la foto. '
              'Probá con una imagen JPG o PNG.',
          'Não foi possível salvar a foto. '
              'Tente uma imagem JPG ou PNG.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  Future<void> _quitarFoto() async {
    if (_cargando || _repositorio == null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Quitar foto', 'Remover foto')),
        content: Text(
          _t(
            '¿Querés quitar tu foto personalizada? '
                'Se mostrará el ícono predeterminado.',
            'Deseja remover sua foto personalizada? '
                'O ícone padrão será exibido.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_textos.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_textos.commonDelete),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _cargando = true);

    try {
      await _repositorio!.usuario.update({
        'fotoPerfilBytes': AppFieldValue.delete(),
        'fotoPerfilActualizada': AppFieldValue.delete(),
      });

      _mensaje(_t('Foto eliminada.', 'Foto removida.'));
    } catch (error) {
      _mensaje(
        _t('No se pudo quitar la foto.', 'Não foi possível remover a foto.'),
      );
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  // =====================================================
  // INFORMACIÓN ACADÉMICA MEDIANTE LA API
  // =====================================================

  Future<void> _editarInformacionAcademica(Map<String, dynamic> datos) async {
    if (_repositorio == null || _cargando) return;

    final formulario = GlobalKey<FormState>();

    String institucion = datos['institucion']?.toString() ?? '';
    String carrera = datos['carrera']?.toString() ?? '';
    String semestre = datos['semestre']?.toString() ?? '';
    String metaAcademica = datos['metaAcademica']?.toString() ?? '';

    final resultado = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_textos.profileAcademicData),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Form(
              key: formulario,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: institucion,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: _textos.profileInstitution,
                      hintText: 'IFSul',
                    ),
                    onChanged: (valor) => institucion = valor,
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    initialValue: carrera,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: _textos.profileDegree,
                    ),
                    onChanged: (valor) => carrera = valor,
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    initialValue: semestre,
                    maxLength: 30,
                    decoration: InputDecoration(
                      labelText: _textos.profileSemester,
                    ),
                    onChanged: (valor) => semestre = valor,
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    initialValue: metaAcademica,
                    maxLength: 120,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: _textos.profileAcademicGoal,
                    ),
                    onChanged: (valor) => metaAcademica = valor,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_textos.commonCancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (!formulario.currentState!.validate()) {
                return;
              }

              Navigator.pop(dialogContext, {
                'institucion': institucion.trim(),
                'carrera': carrera.trim(),
                'semestre': semestre.trim(),
                'metaAcademica': metaAcademica.trim(),
              });
            },
            child: Text(_textos.commonSave),
          ),
        ],
      ),
    );

    if (resultado == null) return;

    setState(() => _cargando = true);

    try {
      await _repositorio!.guardarPerfilAcademico(
        institucion: resultado['institucion'] ?? '',
        carrera: resultado['carrera'] ?? '',
        semestre: resultado['semestre'] ?? '',
        metaAcademica: resultado['metaAcademica'] ?? '',
      );

      _mensaje(_textos.profileSaveSuccess);
    } catch (error) {
      _mensaje(
        _t(
          'No se pudieron guardar los datos.',
          'Não foi possível salvar os dados.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  // =====================================================
  // PREFERENCIAS EN UN SOLO LUGAR
  // =====================================================

  Future<void> _abrirPreferencias() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, actualizarDialogo) {
            final textos = AppLocalizations.of(dialogContext);

            return AlertDialog(
              title: Text(textos.profilePreferences),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // IDIOMA
                      DropdownButtonFormField<String>(
                        key: ValueKey(languageController.languageCode),
                        initialValue: languageController.languageCode,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: textos.profileLanguage,
                          prefixIcon: const Icon(Icons.language),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'es',
                            child: Text('🇺🇾 Español'),
                          ),
                          DropdownMenuItem(
                            value: 'pt_BR',
                            child: Text('🇧🇷 Português (Brasil)'),
                          ),
                        ],
                        onChanged: (valor) async {
                          if (valor == null) return;

                          try {
                            await languageController.setLanguage(valor);

                            if (dialogContext.mounted) {
                              actualizarDialogo(() {});
                            }
                          } catch (error) {
                            _mensaje(
                              _t(
                                'No se pudo cambiar el idioma.',
                                'Não foi possível alterar o idioma.',
                              ),
                            );
                          }
                        },
                      ),

                      const SizedBox(height: 16),
                      const Divider(),

                      // MODO OSCURO
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.dark_mode_outlined),
                        title: Text(textos.profileDarkMode),
                        value: StudyTrackThemeController.modoOscuroActivado,
                        onChanged: (valor) async {
                          try {
                            await StudyTrackThemeController.cambiarModoOscuro(
                              valor,
                            );

                            if (dialogContext.mounted) {
                              actualizarDialogo(() {});
                            }
                          } catch (error) {
                            _mensaje(
                              _t(
                                'No se pudo guardar el tema.',
                                'Não foi possível salvar o tema.',
                              ),
                            );
                          }
                        },
                      ),

                      const Divider(),

                      // MOSTRAR CORREO
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.email_outlined),
                        title: Text(_t('Mostrar correo', 'Mostrar e-mail')),
                        value: _mostrarCorreo,
                        onChanged: (valor) async {
                          setState(() => _mostrarCorreo = valor);
                          actualizarDialogo(() {});

                          try {
                            await _preferencias.setBool(
                              _clave('mostrar_correo'),
                              valor,
                            );
                          } catch (error) {
                            _mensaje(
                              _t(
                                'No se pudo guardar la preferencia.',
                                'Não foi possível salvar a preferência.',
                              ),
                            );
                          }
                        },
                      ),

                      const Divider(),

                      // ACCESIBILIDAD
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.text_fields),
                        title: Text(textos.profileFontSize),
                        subtitle: Text(
                          _t(
                            'Texto más grande en Perfil',
                            'Texto maior no Perfil',
                          ),
                        ),
                        value: _letraGrande,
                        onChanged: (valor) async {
                          setState(() => _letraGrande = valor);
                          actualizarDialogo(() {});

                          try {
                            await _preferencias.setBool(
                              _clave('letra_grande'),
                              valor,
                            );
                          } catch (error) {
                            _mensaje(
                              _t(
                                'No se pudo guardar la preferencia.',
                                'Não foi possível salvar a preferência.',
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(textos.commonClose),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =====================================================
  // VERIFICACIÓN DE CORREO
  // =====================================================

  Future<void> _verificacionCorreo({required bool enviar}) async {
    final user = _usuario;

    if (user == null) return;

    try {
      await user.reload();

      final actualizado = _usuario;

      if (actualizado == null) return;

      if (enviar) {
        if (actualizado.emailVerified) {
          _mensaje(
            _t('El correo ya está verificado.', 'O e-mail já está verificado.'),
          );
          return;
        }

        await FirebaseAuth.instance.setLanguageCode(
          languageController.locale.languageCode,
        );

        await actualizado.sendEmailVerification();

        _mensaje(
          _t(
            'Enviamos un enlace a tu correo.',
            'Enviamos um link para seu e-mail.',
          ),
        );
      } else {
        _mensaje(
          actualizado.emailVerified
              ? _t('Tu correo está verificado.', 'Seu e-mail está verificado.')
              : _t(
                  'Tu correo todavía no está verificado.',
                  'Seu e-mail ainda não está verificado.',
                ),
        );
      }

      if (mounted) setState(() {});
    } on FirebaseAuthException catch (error) {
      _mensaje(
        error.code == 'too-many-requests'
            ? _t(
                'Demasiados intentos. Probá más tarde.',
                'Muitas tentativas. Tente mais tarde.',
              )
            : _t(
                'No se pudo completar la verificación.',
                'Não foi possível concluir a verificação.',
              ),
      );
    } catch (error) {
      _mensaje(
        _t(
          'Ocurrió un error con la verificación.',
          'Ocorreu um erro na verificação.',
        ),
      );
    }
  }

  // =====================================================
  // CAMBIO DE CONTRASEÑA
  // =====================================================

  Future<void> _cambiarContrasena() async {
    final user = _usuario;

    if (user == null || _cargando) return;

    final tienePassword = user.providerData.any(
      (p) => p.providerId == 'password',
    );

    if (!tienePassword) {
      await _informacion(
        _t('Seguridad', 'Segurança'),
        _t(
          'Esta cuenta utiliza Google. '
              'La contraseña de Google se administra '
              'desde la configuración de Google.',
          'Esta conta utiliza o Google. '
              'A senha é gerenciada nas configurações '
              'da sua conta Google.',
        ),
      );
      return;
    }

    final correo = user.email;

    if (correo == null || correo.isEmpty) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Cambiar contraseña', 'Alterar senha')),
        content: Text(
          _t(
            '¿Querés recibir un enlace de recuperación '
                'en $correo?',
            'Deseja receber um link para redefinir '
                'a senha em $correo?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_textos.commonCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('Enviar correo', 'Enviar e-mail')),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _cargando = true);

    try {
      await FirebaseAuth.instance.setLanguageCode(
        languageController.locale.languageCode,
      );

      await FirebaseAuth.instance.sendPasswordResetEmail(email: correo);

      _mensaje(
        _t(
          'Revisá tu correo para cambiar la contraseña.',
          'Verifique seu e-mail para alterar a senha.',
        ),
      );
    } catch (error) {
      _mensaje(
        _t('No se pudo enviar el correo.', 'Não foi possível enviar o e-mail.'),
      );
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  // =====================================================
  // PRIVACIDAD
  // =====================================================

  Future<void> _abrirPrivacidad() async {
    await _informacion(
      _t('Privacidad', 'Privacidade'),
      _t(
        'StudyTrack utiliza Firebase Authentication '
            'para administrar el inicio de sesión.\n\n'
            'Los datos académicos y la foto personalizada '
            'se guardan en Supabase mediante la API de StudyTrack.\n\n'
            'La foto es una miniatura comprimida y no '
            'modifica la foto de tu cuenta Google.\n\n'
            'Las preferencias de idioma, apariencia '
            'y accesibilidad se guardan localmente.\n\n'
            'Esta información no sustituye una política '
            'de privacidad completa.',
        'O StudyTrack utiliza Firebase Authentication '
            'para gerenciar o login.\n\n'
            'Os dados acadêmicos e a foto personalizada '
            'são salvos no Supabase pela API do StudyTrack.\n\n'
            'A foto é uma miniatura compactada e não '
            'altera a foto da sua conta Google.\n\n'
            'As preferências de idioma, aparência '
            'e acessibilidade são salvas localmente.\n\n'
            'Estas informações não substituem uma '
            'política de privacidade completa.',
      ),
    );
  }

  // =====================================================
  // CERRAR SESIÓN
  // =====================================================

  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_textos.authLogout),
        content: Text(
          _t('¿Querés salir de StudyTrack?', 'Deseja sair do StudyTrack?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_textos.commonCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_textos.authLogout),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    String? aviso;

    try {
      await ApiClient.instance.signOut();
    } catch (error) {
      aviso = error is ApiException
          ? error.message
          : _t(
              'No se pudo confirmar el cierre de la sesión en el servidor.',
              'Não foi possível confirmar o encerramento da sessão no servidor.',
            );
    } finally {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (error) {
        aviso = _t(
          'No se pudo confirmar el cierre de la sesión de Firebase.',
          'Não foi possível confirmar o encerramento da sessão do Firebase.',
        );
      }
    }

    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
    if (aviso != null) {
      messenger.showSnackBar(SnackBar(content: Text(aviso)));
    }
  }

  // =====================================================
  // ELIMINAR CUENTA - VERIFICACIÓN DE IDENTIDAD
  // =====================================================

  Future<bool> _verificarIdentidadParaEliminar(User usuario) async {
    final proveedores = usuario.providerData
        .map((proveedor) => proveedor.providerId)
        .toSet();

    try {
      if (proveedores.contains('google.com')) {
        final proveedorGoogle = GoogleAuthProvider();
        final resultado = kIsWeb
            ? await usuario.reauthenticateWithPopup(proveedorGoogle)
            : await usuario.reauthenticateWithProvider(proveedorGoogle);

        return resultado.user?.uid == usuario.uid &&
            FirebaseAuth.instance.currentUser?.uid == usuario.uid;
      }

      if (proveedores.contains('password')) {
        final correo = usuario.email;
        if (correo == null || correo.isEmpty || !mounted) return false;

        String contrasenaIngresada = '';
        final contrasena = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, actualizarDialogo) => AlertDialog(
              title: Text(_t('Verificar identidad', 'Verificar identidade')),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      color: bordo,
                      size: 40,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _t(
                        'Ingresá tu contraseña actual para confirmar '
                            'que sos el propietario de esta cuenta.',
                        'Digite sua senha atual para confirmar '
                            'que você é o proprietário desta conta.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: _t('Contraseña actual', 'Senha atual'),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                      onChanged: (valor) {
                        actualizarDialogo(() => contrasenaIngresada = valor);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(_textos.commonCancel),
                ),
                FilledButton(
                  onPressed: contrasenaIngresada.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, contrasenaIngresada),
                  child: Text(_t('Verificar', 'Verificar')),
                ),
              ],
            ),
          ),
        );

        if (contrasena == null || contrasena.isEmpty) return false;
        final resultado = await usuario.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: correo, password: contrasena),
        );
        return resultado.user?.uid == usuario.uid &&
            FirebaseAuth.instance.currentUser?.uid == usuario.uid;
      }

      if (!mounted) return false;
      await _informacion(
        _t('Verificación no disponible', 'Verificação indisponível'),
        _t(
          'Este método de inicio de sesión todavía no permite '
              'verificar la identidad para eliminar la cuenta.',
          'Este método de login ainda não permite verificar '
              'a identidade para excluir a conta.',
        ),
      );
      return false;
    } on FirebaseAuthException catch (error) {
      if (!mounted) return false;
      if (error.code == 'popup-closed-by-user' ||
          error.code == 'cancelled-popup-request') {
        return false;
      }

      final mensaje = switch (error.code) {
        'wrong-password' || 'invalid-credential' => _t(
          'Contraseña o credenciales incorrectas.',
          'Senha ou credenciais incorretas.',
        ),
        'user-mismatch' => _t(
          'La cuenta seleccionada no coincide con la actual.',
          'A conta selecionada não corresponde à conta atual.',
        ),
        'too-many-requests' => _t(
          'Demasiados intentos. Probá más tarde.',
          'Muitas tentativas. Tente novamente mais tarde.',
        ),
        _ => _t(
          'No se pudo verificar tu identidad. Intentá nuevamente.',
          'Não foi possível verificar sua identidade. Tente novamente.',
        ),
      };
      _mensaje(mensaje);
      return false;
    } catch (error) {
      debugPrint('Error verificando identidad: $error');
      if (mounted) {
        _mensaje(
          _t(
            'No fue posible verificar tu identidad.',
            'Não foi possível verificar sua identidade.',
          ),
        );
      }
      return false;
    }
  }

  // =====================================================
  // ELIMINACIÓN REAL EN FIREBASE AUTHENTICATION
  // =====================================================

  Future<void> _solicitarEliminacionCuenta() async {
    if (_cargando) return;

    final usuario = _usuario;
    final correo = usuario?.email;

    if (usuario == null || correo == null || correo.isEmpty) {
      _mensaje(
        _t(
          'No se pudo identificar tu cuenta.',
          'Não foi possível identificar sua conta.',
        ),
      );
      return;
    }

    // Paso 1: correo, palabra ELIMINAR y espera de 30 segundos.
    final confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConfirmarEliminacionDialog(
        correo: correo,
        portugues: languageController.locale.languageCode == 'pt',
      ),
    );
    if (!mounted || confirmado != true) return;

    // Paso 2: reautenticación real con el proveedor de Firebase.
    final identidadVerificada = await _verificarIdentidadParaEliminar(usuario);
    if (!mounted || !identidadVerificada) return;

    // Nunca eliminamos una cuenta distinta de la sesión inicial.
    if (FirebaseAuth.instance.currentUser?.uid != usuario.uid) {
      _mensaje(
        _t(
          'La sesión cambió. Operación cancelada.',
          'A sessão mudou. Operação cancelada.',
        ),
      );
      return;
    }

    // Paso 3: advertencia explícita sobre los datos que aún
    // permanecen en Supabase. Es la última opción de cancelar.
    final eliminarSoloFirebase = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Última confirmación', 'Última confirmação')),
        content: Text(
          _t(
            'Esta versión eliminará realmente tu cuenta de Firebase '
                'Authentication. Sin embargo, tus materias, tareas '
                'y otros datos almacenados en Supabase NO se borrarán '
                'todavía y podrían quedar inaccesibles.\n\n'
                'Usá solamente una cuenta de prueba. ¿Querés continuar?',
            'Esta versão excluirá de verdade sua conta do Firebase '
                'Authentication. Porém, suas disciplinas, tarefas '
                'e outros dados armazenados no Supabase NÃO serão '
                'excluídos ainda e poderão ficar inacessíveis.\n\n'
                'Use apenas uma conta de teste. Deseja continuar?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_textos.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              _t('Eliminar solo Firebase', 'Excluir apenas Firebase'),
            ),
          ),
        ],
      ),
    );
    if (!mounted || eliminarSoloFirebase != true) return;

    // La cuenta no debe haber cambiado durante la confirmación final.
    if (FirebaseAuth.instance.currentUser?.uid != usuario.uid) {
      _mensaje(
        _t(
          'La sesión cambió. Operación cancelada.',
          'A sessão mudou. Operação cancelada.',
        ),
      );
      return;
    }

    setState(() => _cargando = true);
    try {
      // Paso 4: BORRADO REAL del usuario actual de Firebase Auth.
      // ATENCIÓN: NO elimina los registros de Supabase.
      await usuario.delete();

      // Limpiar la sesión de la API aun si el servidor responde 401.
      try {
        await ApiClient.instance.signOut();
      } catch (error) {
        debugPrint('No se pudo cerrar sesión en la API: $error');
      }

      // Firebase suele cerrar la sesión al eliminar la cuenta.
      // Forzamos el cierre si aún queda una sesión local.
      try {
        await FirebaseAuth.instance.signOut();
      } catch (error) {
        debugPrint('No se pudo limpiar la sesión Firebase: $error');
      }

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Cuenta de Firebase eliminada. Los datos de Supabase '
                  'siguen pendientes de eliminación.',
              'Conta do Firebase excluída. Os dados do Supabase '
                  'ainda precisam ser excluídos.',
            ),
          ),
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      _mensaje(
        error.code == 'requires-recent-login'
            ? _t(
                'Por seguridad, volvé a iniciar sesión y '
                    'reintentá la eliminación.',
                'Por segurança, entre novamente na conta '
                    'e tente excluir outra vez.',
              )
            : _t(
                'No se pudo eliminar la cuenta de Firebase: ${error.code}',
                'Não foi possível excluir a conta do Firebase: ${error.code}',
              ),
      );
    } catch (error) {
      debugPrint('Error eliminando la cuenta de Firebase: $error');
      if (mounted) {
        _mensaje(
          _t(
            'No fue posible confirmar la eliminación.',
            'Não foi possível confirmar a exclusão.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // =====================================================
  // COMPONENTES VISUALES
  // =====================================================

  Widget _tituloSeccion(String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          texto.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _opcion({
    required IconData icono,
    required String titulo,
    String? subtitulo,
    required VoidCallback? onTap,
    bool peligro = false,
  }) {
    final tema = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: Icon(
          icono,
          color: peligro ? tema.colorScheme.error : _colorAcento(context),
        ),
        title: Text(
          titulo,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: peligro ? tema.colorScheme.error : null,
          ),
        ),
        subtitle: subtitulo == null ? null : Text(subtitulo),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _encabezado(Map<String, dynamic> datos) {
    final tema = Theme.of(context);
    final user = _usuario;

    // Mostrar la foto personalizada guardada en el perfil.
    // Nunca tomamos la fotografía de Google.
    final valorFoto = datos['fotoPerfilBytes'];

    Uint8List? foto;

    if (valorFoto is AppBlob) {
      foto = valorFoto.bytes;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 52,
                  backgroundColor: _fondoIcono(context),
                  backgroundImage: foto == null ? null : MemoryImage(foto),
                  child: foto == null
                      ? Icon(
                          Icons.person,
                          size: 56,
                          color: _colorAcento(context),
                        )
                      : null,
                ),

                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Material(
                    color: _colorAcento(context),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: _t('Cambiar foto', 'Alterar foto'),
                      onPressed: _cargando ? null : _cambiarFoto,
                      icon: Icon(
                        Icons.camera_alt,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.black
                            : Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Text(
              _nombreUsuario,
              textAlign: TextAlign.center,
              style: tema.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            if (_mostrarCorreo)
              Text(
                user?.email ?? _t('Sin correo', 'Sem e-mail'),
                textAlign: TextAlign.center,
                style: tema.textTheme.bodyMedium,
              ),

            const SizedBox(height: 10),

            if (user != null)
              Chip(
                avatar: Icon(
                  user.emailVerified
                      ? Icons.verified
                      : Icons.warning_amber_outlined,
                  color: user.emailVerified
                      ? Colors.green
                      : _colorAcento(context),
                ),
                label: Text(
                  user.emailVerified
                      ? _textos.authEmailVerified
                      : _textos.authEmailNotVerified,
                ),
              ),

            const SizedBox(height: 4),

            Text(_proveedorCuenta, style: tema.textTheme.bodySmall),

            if (user != null && !user.emailVerified) ...[
              const SizedBox(height: 8),

              TextButton(
                onPressed: () => _verificacionCorreo(enviar: true),
                child: Text(_t('Enviar verificación', 'Enviar verificação')),
              ),

              TextButton(
                onPressed: () => _verificacionCorreo(enviar: false),
                child: Text(_t('Actualizar estado', 'Atualizar status')),
              ),
            ],

            const SizedBox(height: 16),

            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _cargando ? null : _cambiarFoto,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(_t('Cambiar foto', 'Alterar foto')),
                ),

                if (foto != null)
                  OutlinedButton.icon(
                    onPressed: _cargando ? null : _quitarFoto,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(_t('Quitar foto', 'Remover foto')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // PANTALLA PRINCIPAL
  // =====================================================

  @override
  Widget build(BuildContext context) {
    if (_usuario == null || _repositorio == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_textos.profileTitle),
          backgroundColor: bordo,
          foregroundColor: Colors.white,
        ),
        body: Center(child: Text(_textos.errorsNotSignedIn)),
      );
    }

    final media = MediaQuery.of(context);
    final escalaSistema = media.textScaler.scale(14) / 14;

    final escala = escalaSistema * (_letraGrande ? 1.18 : 1.0);

    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(escala)),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _textos.profileTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: bordo,
          foregroundColor: Colors.white,
        ),

        body: StreamBuilder<AppDocument>(
          stream: _perfilStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  _t(
                    'No se pudo cargar el perfil. '
                        'Revisá la conexión y volvé a intentarlo.',
                    'Não foi possível carregar o perfil. '
                        'Verifique a conexão e tente novamente.',
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            }

            if (!snapshot.hasData) {
              return Center(
                child: CircularProgressIndicator(color: _colorAcento(context)),
              );
            }

            final datos = snapshot.data!.data() ?? <String, dynamic>{};

            final carrera = datos['carrera']?.toString() ?? '';

            final institucion = datos['institucion']?.toString() ?? '';

            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _encabezado(datos),

                        const SizedBox(height: 12),

                        _tituloSeccion(
                          _t('Mi información', 'Minhas informações'),
                        ),

                        _opcion(
                          icono: Icons.edit_outlined,
                          titulo: _textos.profileEditName,
                          subtitulo: _nombreUsuario,
                          onTap: _cargando ? null : _editarNombre,
                        ),

                        _opcion(
                          icono: Icons.school_outlined,
                          titulo: _textos.profileAcademicData,
                          subtitulo: carrera.isNotEmpty
                              ? carrera
                              : institucion.isNotEmpty
                              ? institucion
                              : _t(
                                  'Agregar institución y carrera',
                                  'Adicionar instituição e curso',
                                ),
                          onTap: _cargando
                              ? null
                              : () => _editarInformacionAcademica(datos),
                        ),

                        _tituloSeccion(_textos.profilePreferences),

                        _opcion(
                          icono: Icons.tune_outlined,
                          titulo: _textos.profilePreferences,
                          subtitulo: _t(
                            'Idioma, tema, correo y texto',
                            'Idioma, tema, e-mail e texto',
                          ),
                          onTap: _abrirPreferencias,
                        ),

                        // SUSCRIPCIÓN
                        _tituloSeccion(
                          _t('Mi suscripción', 'Minha assinatura'),
                        ),

                        _opcion(
                          icono: Icons.workspace_premium_outlined,
                          titulo: _t(
                            'Planes Free y Premium',
                            'Planos Free e Premium',
                          ),
                          subtitulo: _t(
                            'Comparar beneficios y gestionar mi plan',
                            'Comparar benefícios e gerenciar meu plano',
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const PaywallScreen(),
                              ),
                            );
                          },
                        ),

                        _tituloSeccion(
                          _t(
                            'Seguridad y privacidad',
                            'Segurança e privacidade',
                          ),
                        ),

                        _opcion(
                          icono: Icons.lock_outline,
                          titulo: _t('Cambiar contraseña', 'Alterar senha'),
                          subtitulo: _t(
                            'Recuperación por correo',
                            'Recuperação por e-mail',
                          ),
                          onTap: _cargando ? null : _cambiarContrasena,
                        ),

                        _opcion(
                          icono: Icons.shield_outlined,
                          titulo: _t('Privacidad', 'Privacidade'),
                          onTap: _abrirPrivacidad,
                        ),

                        const SizedBox(height: 16),

                        _opcion(
                          icono: Icons.logout,
                          titulo: _textos.authLogout,
                          peligro: true,
                          onTap: _cargando ? null : _cerrarSesion,
                        ),

                        // ELIMINAR CUENTA - OPCION DISCRETA
                        const SizedBox(height: 8),

                        Card(
                          margin: const EdgeInsets.only(bottom: 9),
                          elevation: 0,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF312628)
                              : const Color(0xFFFBF5F6),
                          child: ListTile(
                            leading: const Icon(
                              Icons.delete_outline,
                              color: Color(0xFF9B626A),
                            ),
                            title: Text(
                              _t('Eliminar cuenta', 'Excluir conta'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? const Color(0xFFDCA8AF)
                                    : const Color(0xFF965E66),
                              ),
                            ),
                            subtitle: Text(
                              _t(
                                'Acción permanente e irreversible',
                                'Ação permanente e irreversível',
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: _cargando
                                ? null
                                : _solicitarEliminacionCuenta,
                          ),
                        ),

                        if (_cargando)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: _colorAcento(context),
                              ),
                            ),
                          ),

                        const SizedBox(height: 20),

                        Center(
                          child: Text(
                            'StudyTrack v1.0',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
