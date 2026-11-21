import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../l10n/app_localizations.dart';
import '../services/language_controller.dart';
import '../services/studytrack_repository.dart';
import '../services/notification_service.dart';
import '../services/plan_service.dart';

// =====================================================
// COLORES INSTITUCIONALES
// =====================================================

const Color _bordoInstitucional = Color(0xFF670810);

Color _colorAcento(BuildContext context) {
  final esOscuro = Theme.of(context).brightness == Brightness.dark;

  return esOscuro ? const Color(0xFFE57373) : _bordoInstitucional;
}

Color _textoSobreAcento(BuildContext context) {
  final esOscuro = Theme.of(context).brightness == Brightness.dark;

  return esOscuro ? Colors.black : Colors.white;
}

// =====================================================
// TRADUCCIONES COMPLEMENTARIAS
// =====================================================

// Las traducciones existentes utilizan AppLocalizations.
// Esta función cubre los mensajes que todavía no tienen
// una clave en los archivos ARB.
//
// Utiliza el idioma seleccionado en StudyTrack.

String _t(String es, String pt) {
  return languageController.isPortuguese ? pt : es;
}

// =====================================================
// PANTALLA DE GESTIÓN DE TAREAS
// =====================================================

// Las tareas se guardan en Firebase y se sincronizan
// con el Dashboard y el Wearable.

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  static const Color bordo = _bordoInstitucional;

  bool guardando = false;

  // Las notificaciones locales se programan en Android.
  // En Web/Windows seguimos guardando las tareas en Firebase.
  bool get _esAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // =====================================================
  // IDENTIFICADORES DE NOTIFICACIONES
  // =====================================================

  int _generarIdNotificacion() {
    return DateTime.now().microsecondsSinceEpoch.remainder(2147483647);
  }

  int? _obtenerIdNotificacion(Map<String, dynamic> datos) {
    final valor = datos['notificacionId'];

    return valor is num ? valor.toInt() : null;
  }

  Future<void> _cancelarNotificacion(Map<String, dynamic> datos) async {
    if (!_esAndroid) return;

    final id = _obtenerIdNotificacion(datos);

    if (id != null) {
      await NotificationService.cancelarRecordatorio(id);
    }
  }

  // =====================================================
  // FUNCIONES DE FECHA
  // =====================================================

  DateTime? obtenerFecha(Object? valor) {
    if (valor is Timestamp) {
      return valor.toDate();
    }

    if (valor is DateTime) {
      return valor;
    }

    return null;
  }

  String formatearFecha(DateTime? fecha) {
    if (fecha == null) {
      return _t('Sin fecha de entrega', 'Sem data de entrega');
    }

    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final hora = fecha.hour.toString().padLeft(2, '0');
    final minuto = fecha.minute.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year} - $hora:$minuto';
  }

  // =====================================================
  // MOSTRAR MENSAJES
  // =====================================================

  void mostrarMensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _mostrarLimiteTareas() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Función Premium 🔒', 'Recurso Premium 🔒')),
        content: Text(_t(
          'El plan Free permite crear hasta 5 tareas.\n\n'
          'Activá Premium para crear tareas ilimitadas.',
          'O plano Free permite criar até 5 tarefas.\n\n'
          'Ative o Premium para criar tarefas ilimitadas.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('Entendido', 'Entendi')),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // CREAR UNA TAREA EN FIREBASE Y PROGRAMAR SU AVISO
  // =====================================================

  Future<void> agregarTarea(StudyTrackRepository repositorio) async {
    if (guardando) return;

    // El límite Free se calcula sobre las tareas persistidas en Firestore.
    // Así no se reinicia al salir de esta pantalla.
    Future<bool> tieneCupo() async {
      final consulta = await repositorio.tareas.get();
      return PlanService.puedeCrearTarea(consulta.docs.length);
    }

    try {
      if (!await tieneCupo()) {
        if (!mounted) return;
        await _mostrarLimiteTareas();
        return;
      }
    } catch (error) {
      debugPrint('Error al verificar el plan de tareas: $error');
      mostrarMensaje(_t(
        'No se pudo verificar el límite de tareas.',
        'Não foi possível verificar o limite de tarefas.',
      ));
      return;
    }

    if (!mounted) return;
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _NuevaTareaDialog(),
    );

    if (!mounted || resultado == null) return;

    final titulo = resultado['titulo'] as String;
    final fechaEntrega = resultado['fecha'] as DateTime;
    final minutosAntes = resultado['minutosAntes'] as int;

    final fechaAviso = fechaEntrega.subtract(Duration(minutes: minutosAntes));

    // Comprobar que el aviso sea futuro.
    if (!fechaAviso.isAfter(DateTime.now())) {
      mostrarMensaje(
        _t(
          'La hora del recordatorio ya pasó. '
              'Elegí otra fecha.',
          'O horário do lembrete já passou. '
              'Escolha outra data.',
        ),
      );

      return;
    }

    setState(() {
      guardando = true;
    });

    try {
      // Revalidar después del diálogo, por si se agregaron tareas
      // desde otro dispositivo mientras el formulario estaba abierto.
      if (!await tieneCupo()) {
        if (mounted) await _mostrarLimiteTareas();
        return;
      }

      final idNotificacion = _generarIdNotificacion();

      // ==========================================
      // GUARDAR EN FIRESTORE
      // ==========================================

      // Se mantienen exactamente los mismos campos
      // para conservar la sincronización con
      // Dashboard, Calendario y Wearable.

      await repositorio.tareas.add({
        'titulo': titulo.trim(),
        'descripcion': '',
        'materiaId': '',
        'fechaEntrega': Timestamp.fromDate(fechaEntrega),
        'prioridad': 'MEDIA',
        'minutosAntes': minutosAntes,
        'notificacionId': idNotificacion,
        'completada': false,
        'creadaEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      // ==========================================
      // WEB / WINDOWS
      // ==========================================

      if (!_esAndroid) {
        mostrarMensaje(
          _t(
            'Tarea guardada en Firebase. '
                'Los avisos locales se programan '
                'desde Android.',
            'Tarefa salva no Firebase. '
                'Os lembretes locais são programados '
                'no Android.',
          ),
        );

        return;
      }

      // ==========================================
      // NOTIFICACIONES EN ANDROID
      // ==========================================

      try {
        await NotificationService.programarRecordatorio(
          id: idNotificacion,
          titulo: titulo,
          fecha: fechaAviso,
        );

        mostrarMensaje(
          _t(
            'Tarea guardada y recordatorio programado.',
            'Tarefa salva e lembrete programado.',
          ),
        );
      } catch (error) {
        debugPrint('No se pudo programar el aviso: $error');

        mostrarMensaje(
          _t(
            'La tarea se guardó, pero no se pudo '
                'programar el aviso.',
            'A tarefa foi salva, mas não foi possível '
                'programar o lembrete.',
          ),
        );
      }
    } catch (error) {
      debugPrint('Error al guardar tarea: $error');

      mostrarMensaje(
        _t('No se pudo guardar la tarea.', 'Não foi possível salvar a tarefa.'),
      );
    } finally {
      if (mounted) {
        setState(() {
          guardando = false;
        });
      }
    }
  }

  // =====================================================
  // COMPLETAR O REACTIVAR UNA TAREA
  // =====================================================

  Future<void> cambiarEstado(
    StudyTrackRepository repositorio,
    QueryDocumentSnapshot<Map<String, dynamic>> tarea,
    bool completada,
  ) async {
    final datos = tarea.data();

    try {
      await repositorio.cambiarEstadoTarea(tarea.id, completada);
    } catch (error) {
      debugPrint('Error al actualizar tarea: $error');

      mostrarMensaje(
        _t(
          'No se pudo actualizar la tarea.',
          'Não foi possível atualizar a tarefa.',
        ),
      );

      return;
    }

    if (!_esAndroid) return;

    try {
      if (completada) {
        // Si la tarea se completó,
        // cancelar el recordatorio.
        await _cancelarNotificacion(datos);
      } else {
        // Si se reactiva la tarea,
        // restaurar su recordatorio cuando sea posible.

        final id = _obtenerIdNotificacion(datos);

        final fecha = obtenerFecha(datos['fechaEntrega']);

        final anticipacion = datos['minutosAntes'];

        if (id != null && fecha != null && anticipacion is num) {
          final fechaAviso = fecha.subtract(
            Duration(minutes: anticipacion.toInt()),
          );

          if (fechaAviso.isAfter(DateTime.now())) {
            await NotificationService.programarRecordatorio(
              id: id,
              titulo: datos['titulo']?.toString() ?? _t('Tarea', 'Tarefa'),
              fecha: fechaAviso,
            );
          } else {
            mostrarMensaje(
              _t(
                'Tarea reactivada, pero ya pasó '
                    'la hora del aviso.',
                'Tarefa reativada, mas o horário '
                    'do lembrete já passou.',
              ),
            );
          }
        }
      }
    } catch (error) {
      debugPrint('Error al actualizar recordatorio: $error');

      mostrarMensaje(
        _t(
          'La tarea se actualizó, pero hubo '
              'un problema con el aviso.',
          'A tarefa foi atualizada, mas houve '
              'um problema com o lembrete.',
        ),
      );
    }
  }

  // =====================================================
  // ELIMINAR UNA TAREA Y CANCELAR SU RECORDATORIO
  // =====================================================

  Future<void> eliminarTarea(
    StudyTrackRepository repositorio,
    QueryDocumentSnapshot<Map<String, dynamic>> tarea,
  ) async {
    final textos = AppLocalizations.of(context);

    final confirmar = await showDialog<bool>(
      context: context,

      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Eliminar tarea', 'Excluir tarefa')),

        content: Text(
          _t('¿Querés eliminar esta tarea?', 'Deseja excluir esta tarefa?'),
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
              style: TextStyle(color: _colorAcento(dialogContext)),
            ),
          ),
        ],
      ),
    );

    if (!mounted || confirmar != true) return;

    // ==========================================
    // ELIMINAR EN FIRESTORE
    // ==========================================

    try {
      await repositorio.eliminarTarea(tarea.id);
    } catch (error) {
      debugPrint('Error al eliminar tarea: $error');

      mostrarMensaje(
        _t(
          'No se pudo eliminar la tarea.',
          'Não foi possível excluir a tarefa.',
        ),
      );

      return;
    }

    // ==========================================
    // CANCELAR EL RECORDATORIO
    // ==========================================

    try {
      await _cancelarNotificacion(tarea.data());

      mostrarMensaje(
        _t(
          'Tarea eliminada y recordatorio cancelado.',
          'Tarefa excluída e lembrete cancelado.',
        ),
      );
    } catch (error) {
      debugPrint('No se pudo cancelar el recordatorio: $error');

      mostrarMensaje(
        _t(
          'Tarea eliminada, pero no se pudo '
              'cancelar el aviso.',
          'Tarefa excluída, mas não foi possível '
              'cancelar o lembrete.',
        ),
      );
    }
  }

  // =====================================================
  // PANTALLA PRINCIPAL
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final usuario = FirebaseAuth.instance.currentUser;
    final textos = AppLocalizations.of(context);

    // ==========================================
    // USUARIO SIN SESIÓN
    // ==========================================

    if (usuario == null) {
      return Scaffold(
        body: Center(
          child: Text(
            _t(
              'Iniciá sesión para ver tus tareas.',
              'Entre na sua conta para ver suas tarefas.',
            ),
          ),
        ),
      );
    }

    final repositorio = StudyTrackRepository(usuario.uid);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      // ==========================================
      // APPBAR
      // ==========================================
      appBar: AppBar(
        backgroundColor: bordo,
        foregroundColor: Colors.white,
        title: Text(textos.navTasks),
      ),

      // ==========================================
      // LISTA DE TAREAS
      // ==========================================
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: repositorio.escucharTareas,

        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                _t(
                  'No se pudieron cargar las tareas.',
                  'Não foi possível carregar as tarefas.',
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(color: _colorAcento(context)),
            );
          }

          final tareas = [...snapshot.data!.docs];

          // ======================================
          // ORDENAR TAREAS
          // ======================================

          // Primero las pendientes.
          // Dentro de cada grupo, ordenar por fecha.

          tareas.sort((a, b) {
            final completadaA = a.data()['completada'] == true;

            final completadaB = b.data()['completada'] == true;

            if (completadaA != completadaB) {
              return completadaA ? 1 : -1;
            }

            final fechaA = obtenerFecha(a.data()['fechaEntrega']);

            final fechaB = obtenerFecha(b.data()['fechaEntrega']);

            if (fechaA == null) return 1;
            if (fechaB == null) return -1;

            return fechaA.compareTo(fechaB);
          });

          // ======================================
          // ESTADO SIN TAREAS
          // ======================================

          if (tareas.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,

                children: [
                  Icon(
                    Icons.assignment_outlined,
                    color: _colorAcento(context),
                    size: 65,
                  ),

                  const SizedBox(height: 16),

                  Text(
                    _t(
                      'Todavía no tenés tareas.',
                      'Você ainda não tem tarefas.',
                    ),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    _t(
                      'Presioná + para crear una.',
                      'Toque em + para criar uma tarefa.',
                    ),
                  ),
                ],
              ),
            );
          }

          // ======================================
          // TAREAS REGISTRADAS
          // ======================================

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tareas.length,

            itemBuilder: (context, index) {
              final tarea = tareas[index];
              final datos = tarea.data();

              final titulo = datos['titulo']?.toString() ?? textos.calendarTask;

              final completada = datos['completada'] == true;

              final fecha = obtenerFecha(datos['fechaEntrega']);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),

                child: ListTile(
                  // =============================
                  // CASILLA COMPLETADA / PENDIENTE
                  // =============================

                  leading: Checkbox(
                    value: completada,
                    activeColor: _colorAcento(context),
                    checkColor: _textoSobreAcento(context),

                    onChanged: (valor) {
                      if (valor == null) return;

                      cambiarEstado(repositorio, tarea, valor);
                    },
                  ),

                  // =============================
                  // NOMBRE DE LA TAREA
                  // =============================
                  title: Text(
                    titulo,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,

                      decoration: completada
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),

                  // =============================
                  // FECHA Y ESTADO TRADUCIDOS
                  // =============================
                  subtitle: Text(
                    '${formatearFecha(fecha)}\n'
                    '${completada ? _t('Completada', 'Concluída') : _t('Pendiente', 'Pendente')}',
                  ),

                  isThreeLine: true,

                  // =============================
                  // ELIMINAR TAREA
                  // =============================
                  trailing: IconButton(
                    tooltip: _t('Eliminar tarea', 'Excluir tarefa'),

                    icon: const Icon(Icons.delete_outline),

                    onPressed: () => eliminarTarea(repositorio, tarea),
                  ),
                ),
              );
            },
          );
        },
      ),

      // ==========================================
      // BOTÓN PARA AGREGAR TAREA
      // ==========================================
      floatingActionButton: FloatingActionButton(
        backgroundColor: _colorAcento(context),
        foregroundColor: _textoSobreAcento(context),

        onPressed: guardando ? null : () => agregarTarea(repositorio),

        child: const Icon(Icons.add),
      ),
    );
  }
}

// =====================================================
// FORMULARIO PARA CREAR UNA NUEVA TAREA
// =====================================================

class _NuevaTareaDialog extends StatefulWidget {
  const _NuevaTareaDialog();

  @override
  State<_NuevaTareaDialog> createState() => _NuevaTareaDialogState();
}

class _NuevaTareaDialogState extends State<_NuevaTareaDialog> {
  final TextEditingController tituloController = TextEditingController();

  late DateTime fecha;

  int minutosAntes = 10;

  // =====================================================
  // INICIALIZAR FECHA
  // =====================================================

  @override
  void initState() {
    super.initState();

    fecha = DateTime.now().add(const Duration(days: 1));
  }

  @override
  void dispose() {
    tituloController.dispose();
    super.dispose();
  }

  // =====================================================
  // SELECCIONAR FECHA Y HORA
  // =====================================================

  Future<void> seleccionarFecha() async {
    final ahora = DateTime.now();

    final dia = await showDatePicker(
      context: context,
      initialDate: fecha,

      firstDate: DateTime(ahora.year, ahora.month, ahora.day),

      lastDate: DateTime(2100),
    );

    if (dia == null || !mounted) return;

    // ==========================================
    // FORMATO DE 24 HORAS
    // ==========================================

    // Se conserva la corrección que permite
    // introducir horas como 13:55 en Flutter Web,
    // tanto con el teclado como con el reloj.

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(fecha),

      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),

          child: child!,
        );
      },
    );

    if (hora == null || !mounted) return;

    setState(() {
      fecha = DateTime(dia.year, dia.month, dia.day, hora.hour, hora.minute);
    });
  }

  // =====================================================
  // VALIDAR Y GUARDAR FORMULARIO
  // =====================================================

  void guardar() {
    final titulo = tituloController.text.trim();

    // ==========================================
    // VALIDAR NOMBRE
    // ==========================================

    if (titulo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Ingresá un nombre para la tarea.',
              'Informe um nome para a tarefa.',
            ),
          ),
        ),
      );

      return;
    }

    // ==========================================
    // VALIDAR FECHA
    // ==========================================

    if (!fecha.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Seleccioná una fecha de entrega futura.',
              'Selecione uma data de entrega futura.',
            ),
          ),
        ),
      );

      return;
    }

    // ==========================================
    // VALIDAR RECORDATORIO
    // ==========================================

    final fechaAviso = fecha.subtract(Duration(minutes: minutosAntes));

    if (!fechaAviso.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Elegí una fecha que permita avisarte '
                  'con anticipación.',
              'Escolha uma data que permita receber '
                  'o lembrete com antecedência.',
            ),
          ),
        ),
      );

      return;
    }

    // ==========================================
    // DEVOLVER LOS DATOS DEL FORMULARIO
    // ==========================================

    Navigator.pop(context, {
      'titulo': titulo,
      'fecha': fecha,
      'minutosAntes': minutosAntes,
    });
  }

  // =====================================================
  // DISEÑO DEL FORMULARIO
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final textos = AppLocalizations.of(context);

    return AlertDialog(
      // ==========================================
      // TÍTULO
      // ==========================================

      title: Text(_t('Nueva tarea', 'Nova tarefa')),

      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            // =====================================
            // NOMBRE DE LA TAREA
            // =====================================

            TextField(
              controller: tituloController,

              decoration: InputDecoration(
                labelText: _t('Nombre de la tarea', 'Nome da tarefa'),

                border: const OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            // =====================================
            // FECHA DE ENTREGA
            // =====================================
            ListTile(
              leading: Icon(Icons.calendar_today, color: _colorAcento(context)),

              title: Text(_t('Fecha de entrega', 'Data de entrega')),

              subtitle: Text(
                '${fecha.day}/${fecha.month}/${fecha.year} '
                '${fecha.hour.toString().padLeft(2, '0')}:'
                '${fecha.minute.toString().padLeft(2, '0')}',
              ),

              onTap: seleccionarFecha,
            ),

            const SizedBox(height: 16),

            // =====================================
            // RECORDATORIOS
            // =====================================
            DropdownButtonFormField<int>(
              initialValue: minutosAntes,

              decoration: InputDecoration(
                labelText: _t('Recordarme antes', 'Lembrar com antecedência'),

                prefixIcon: Icon(
                  Icons.notifications_active_outlined,
                  color: _colorAcento(context),
                ),

                border: const OutlineInputBorder(),
              ),

              items: [
                DropdownMenuItem(
                  value: 5,

                  child: Text(_t('5 minutos antes', '5 minutos antes')),
                ),

                DropdownMenuItem(
                  value: 10,

                  child: Text(_t('10 minutos antes', '10 minutos antes')),
                ),

                DropdownMenuItem(
                  value: 30,

                  child: Text(_t('30 minutos antes', '30 minutos antes')),
                ),

                DropdownMenuItem(
                  value: 60,

                  child: Text(_t('1 hora antes', '1 hora antes')),
                ),
              ],

              onChanged: (valor) {
                if (valor == null) return;

                setState(() {
                  minutosAntes = valor;
                });
              },
            ),
          ],
        ),
      ),

      // ==========================================
      // BOTONES DEL FORMULARIO
      // ==========================================
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),

          style: TextButton.styleFrom(foregroundColor: _colorAcento(context)),

          child: Text(textos.commonCancel),
        ),

        ElevatedButton(
          onPressed: guardar,

          style: ElevatedButton.styleFrom(
            backgroundColor: _colorAcento(context),
            foregroundColor: _textoSobreAcento(context),
          ),

          child: Text(textos.commonSave),
        ),
      ],
    );
  }
}
