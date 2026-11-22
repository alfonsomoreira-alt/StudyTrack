import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/app_data.dart';

import '../l10n/app_localizations.dart';
import '../services/studytrack_repository.dart';

class MateriasScreen extends StatefulWidget {
  const MateriasScreen({super.key});

  @override
  State<MateriasScreen> createState() => _MateriasScreenState();
}

class _MateriasScreenState extends State<MateriasScreen> {
  // ============================================
  // COLORES DE STUDYTRACK
  // ============================================

  // El AppBar conserva el bordó institucional
  // tanto en modo claro como en modo oscuro.
  static const Color bordo = Color(0xFF670810);

  // Los acentos cambian en el modo oscuro.
  Color _colorAcento(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;

    return esOscuro ? const Color(0xFFE57373) : bordo;
  }

  // Fondo suave para los íconos.
  Color _fondoIcono(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;

    return esOscuro
        ? const Color(0xFFE57373).withValues(alpha: 0.16)
        : const Color(0xFFF4E9EB);
  }

  // ============================================
  // TRADUCCIONES
  // ============================================

  // Los textos que ya existen en los archivos
  // ARB se obtienen con AppLocalizations.
  //
  // Esta función permite traducir otros mensajes
  // sin modificar los archivos ARB existentes.

  String _t(BuildContext context, String es, String pt) {
    final idioma = Localizations.localeOf(context).languageCode;

    return idioma == 'pt' ? pt : es;
  }

  // Corregir singular y plural.
  String _contadorMaterias(BuildContext context, int cantidad) {
    if (cantidad == 1) {
      return _t(context, '1 materia registrada', '1 disciplina cadastrada');
    }

    return _t(
      context,
      '$cantidad materias registradas',
      '$cantidad disciplinas cadastradas',
    );
  }

  // ============================================
  // MOSTRAR MENSAJES
  // ============================================

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // ============================================
  // AGREGAR O EDITAR UNA MATERIA
  // ============================================

  Future<void> _abrirFormulario(
    StudyTrackRepository repositorio, {
    AppQueryDocument? documento,
  }) async {
    final textos = AppLocalizations.of(context);

    // Guardamos las traducciones necesarias antes
    // de abrir el formulario.
    final esPortugues = Localizations.localeOf(context).languageCode == 'pt';

    String traducir(String es, String pt) {
      return esPortugues ? pt : es;
    }

    final datos = documento?.data();

    final formulario = GlobalKey<FormState>();

    final nombreController = TextEditingController(
      text: datos?['nombre']?.toString() ?? '',
    );

    final docenteController = TextEditingController(
      text: datos?['docente']?.toString() ?? '',
    );

    final descripcionController = TextEditingController(
      text: datos?['descripcion']?.toString() ?? '',
    );

    bool guardando = false;

    final resultado = await showDialog<bool>(
      context: context,

      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, actualizar) {
            return AlertDialog(
              // =================================
              // TÍTULO TRADUCIDO
              // =================================

              title: Text(
                documento == null ? textos.subjectsAdd : textos.subjectsEdit,
              ),

              // =================================
              // FORMULARIO
              // =================================
              content: SizedBox(
                width: 420,

                child: SingleChildScrollView(
                  child: Form(
                    key: formulario,

                    child: Column(
                      mainAxisSize: MainAxisSize.min,

                      children: [
                        // =========================
                        // NOMBRE DE LA MATERIA
                        // =========================

                        TextFormField(
                          controller: nombreController,
                          maxLength: 80,
                          autofocus: true,

                          textCapitalization: TextCapitalization.sentences,

                          decoration: InputDecoration(
                            labelText: textos.subjectsName,
                            border: const OutlineInputBorder(),
                          ),

                          validator: (valor) {
                            if (valor == null || valor.trim().isEmpty) {
                              return traducir(
                                'Ingresá el nombre',
                                'Informe o nome da disciplina',
                              );
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 12),

                        // =========================
                        // DOCENTE
                        // =========================
                        TextFormField(
                          controller: docenteController,
                          maxLength: 80,

                          decoration: InputDecoration(
                            labelText:
                                '${textos.subjectsTeacher} '
                                '(${textos.commonOptional.toLowerCase()})',

                            border: const OutlineInputBorder(),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // =========================
                        // DESCRIPCIÓN
                        // =========================
                        TextFormField(
                          controller: descripcionController,
                          maxLength: 300,
                          maxLines: 3,

                          decoration: InputDecoration(
                            labelText:
                                '${textos.subjectsDescription} '
                                '(${textos.commonOptional.toLowerCase()})',

                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // =================================
              // BOTONES DEL FORMULARIO
              // =================================
              actions: [
                TextButton(
                  onPressed: guardando
                      ? null
                      : () => Navigator.pop(dialogContext, false),

                  child: Text(textos.commonCancel),
                ),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _colorAcento(dialogContext),

                    foregroundColor:
                        Theme.of(dialogContext).brightness == Brightness.dark
                        ? Colors.black
                        : Colors.white,
                  ),

                  onPressed: guardando
                      ? null
                      : () async {
                          if (!formulario.currentState!.validate()) {
                            return;
                          }

                          actualizar(() {
                            guardando = true;
                          });

                          try {
                            // =========================
                            // GUARDAR EN FIREBASE
                            // =========================

                            await repositorio.guardarMateria(
                              id: documento?.id,
                              nombre: nombreController.text,
                              docente: docenteController.text,
                              descripcion: descripcionController.text,
                            );

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, true);
                            }
                          } catch (error) {
                            _mostrarMensaje(
                              '${traducir('No se pudo guardar', 'Não foi possível salvar')}: $error',
                            );

                            if (dialogContext.mounted) {
                              actualizar(() {
                                guardando = false;
                              });
                            }
                          }
                        },

                  child: Text(
                    guardando
                        ? traducir('Guardando...', 'Salvando...')
                        : textos.commonSave,
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    // Liberar los controladores del formulario.
   // nombreController.dispose();
   // docenteController.dispose();
   // descripcionController.dispose();
    //nombreController.dispose();
    
    //docenteController.dispose();
    
    //descripcionController.dispose();

    // ========================================
    // MENSAJE DE CONFIRMACIÓN
    // ========================================

    if (resultado == true) {
      _mostrarMensaje(
        documento == null
            ? traducir(
                'Materia agregada correctamente.',
                'Disciplina adicionada com sucesso.',
              )
            : traducir(
                'Materia actualizada correctamente.',
                'Disciplina atualizada com sucesso.',
              ),
      );
    }
  }

  // ============================================
  // ELIMINAR UNA MATERIA
  // ============================================

  Future<void> _eliminarMateria(
    StudyTrackRepository repositorio,
    AppQueryDocument documento,
  ) async {
    final textos = AppLocalizations.of(context);

    final esPortugues = Localizations.localeOf(context).languageCode == 'pt';

    String traducir(String es, String pt) {
      return esPortugues ? pt : es;
    }

    final nombre =
        documento.data()['nombre']?.toString() ??
        traducir('esta materia', 'esta disciplina');

    // ========================================
    // CONFIRMAR ELIMINACIÓN
    // ========================================

    final confirmar = await showDialog<bool>(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          title: Text(textos.subjectsDelete),

          content: Text(
            traducir(
              '¿Querés eliminar "$nombre"? '
                  'Esta acción no se puede deshacer.',
              'Deseja excluir "$nombre"? '
                  'Esta ação não pode ser desfeita.',
            ),
          ),

          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),

              child: Text(textos.commonCancel),
            ),

            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),

              child: Text(
                textos.commonDelete,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    // ========================================
    // ELIMINACIÓN EN FIREBASE
    // ========================================

    try {
      await repositorio.eliminarMateria(documento.id);

      _mostrarMensaje(textos.subjectsDeleteSuccess);
    } on StateError {
      _mostrarMensaje(
        '${textos.subjectsCannotDelete} '
        '${traducir('No puede eliminarse todavía.', 'Ela ainda não pode ser excluída.')}',
      );
    } catch (error) {
      _mostrarMensaje(
        '${traducir('No se pudo eliminar', 'Não foi possível excluir')}: $error',
      );
    }
  }

  // ============================================
  // PANTALLA PRINCIPAL
  // ============================================

  @override
  Widget build(BuildContext context) {
    final usuario = FirebaseAuth.instance.currentUser;

    final tema = Theme.of(context);

    final textos = AppLocalizations.of(context);

    // ========================================
    // USUARIO SIN SESIÓN
    // ========================================

    if (usuario == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(textos.subjectsTitle),
          backgroundColor: bordo,
          foregroundColor: Colors.white,
        ),

        body: Center(
          child: Text(
            _t(
              context,
              'Iniciá sesión para ver tus materias.',
              'Entre na sua conta para ver suas disciplinas.',
            ),
          ),
        ),
      );
    }

    final repositorio = StudyTrackRepository(usuario.uid);

    return Scaffold(
      backgroundColor: tema.scaffoldBackgroundColor,

      // ========================================
      // APPBAR INSTITUCIONAL
      // ========================================
      appBar: AppBar(
        title: Text(textos.subjectsTitle),
        backgroundColor: bordo,
        foregroundColor: Colors.white,
      ),

      // ========================================
      // ESCUCHAR MATERIAS DESDE FIREBASE
      // ========================================
      body: StreamBuilder<AppQuerySnapshot>(
        stream: repositorio.escucharMaterias,

        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),

                child: Text(
                  _t(
                    context,
                    'No se pudieron cargar las materias. '
                        'Revisá tu conexión y volvé a intentarlo.',
                    'Não foi possível carregar as disciplinas. '
                        'Verifique sua conexão e tente novamente.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(color: _colorAcento(context)),
            );
          }

          // =====================================
          // ORDENAR MATERIAS
          // =====================================

          final materias = [...snapshot.data!.docs];

          materias.sort((a, b) {
            final nombreA = a.data()['nombre']?.toString().toLowerCase() ?? '';

            final nombreB = b.data()['nombre']?.toString().toLowerCase() ?? '';

            return nombreA.compareTo(nombreB);
          });

          // =====================================
          // LISTA DE MATERIAS
          // =====================================

          return ListView(
            padding: const EdgeInsets.all(20),

            children: [
              Text(
                textos.subjectsOrganize,

                style: tema.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              // CONTADOR TRADUCIDO
              Text(
                _contadorMaterias(context, materias.length),
                style: tema.textTheme.bodyMedium,
              ),

              const SizedBox(height: 20),

              // =================================
              // BOTÓN AGREGAR MATERIA
              // =================================
              SizedBox(
                width: double.infinity,
                height: 52,

                child: ElevatedButton.icon(
                  onPressed: () => _abrirFormulario(repositorio),

                  icon: const Icon(Icons.add),

                  label: Text(textos.subjectsAdd),

                  style: ElevatedButton.styleFrom(
                    backgroundColor: _colorAcento(context),

                    foregroundColor: tema.brightness == Brightness.dark
                        ? Colors.black
                        : Colors.white,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // =================================
              // ESTADO SIN MATERIAS
              // =================================
              if (materias.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),

                    child: Column(
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 52,
                          color: _colorAcento(context),
                        ),

                        const SizedBox(height: 16),

                        Text(
                          textos.subjectsNone,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          _t(
                            context,
                            'Presioná Agregar materia para comenzar.',
                            'Toque em Adicionar disciplina para começar.',
                          ),
                          textAlign: TextAlign.center,
                          style: tema.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                )
              // =================================
              // MATERIAS REGISTRADAS
              // =================================
              else
                ...materias.map((materia) {
                  final datos = materia.data();

                  final nombre =
                      datos['nombre']?.toString() ??
                      _t(context, 'Materia', 'Disciplina');

                  final docente = datos['docente']?.toString() ?? '';

                  final descripcion = datos['descripcion']?.toString() ?? '';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),

                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),

                      leading: CircleAvatar(
                        backgroundColor: _fondoIcono(context),

                        child: Icon(
                          Icons.menu_book_outlined,
                          color: _colorAcento(context),
                        ),
                      ),

                      title: Text(
                        nombre,

                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),

                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          if (docente.isNotEmpty)
                            Text(
                              '${textos.subjectsTeacher}: '
                              '$docente',
                            ),

                          if (descripcion.isNotEmpty) Text(descripcion),
                        ],
                      ),

                      // ==========================
                      // MENÚ EDITAR / ELIMINAR
                      // ==========================
                      trailing: PopupMenuButton<String>(
                        tooltip: _t(
                          context,
                          'Opciones de materia',
                          'Opções da disciplina',
                        ),

                        onSelected: (opcion) {
                          if (opcion == 'editar') {
                            _abrirFormulario(repositorio, documento: materia);
                          } else if (opcion == 'eliminar') {
                            _eliminarMateria(repositorio, materia);
                          }
                        },

                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'editar',
                            child: Text(textos.commonEdit),
                          ),

                          PopupMenuItem<String>(
                            value: 'eliminar',
                            child: Text(textos.commonDelete),
                          ),
                        ],
                      ),

                      // Abrir formulario al tocar.
                      onTap: () =>
                          _abrirFormulario(repositorio, documento: materia),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
} //Niklaus
