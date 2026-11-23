import 'dart:async';

import 'package:flutter/material.dart';

class ConfirmarEliminacionDialog extends StatefulWidget {
  final String correo;
  final bool portugues;

  const ConfirmarEliminacionDialog({
    super.key,
    required this.correo,
    required this.portugues,
  });

  @override
  State<ConfirmarEliminacionDialog> createState() =>
      _ConfirmarEliminacionDialogState();
}

class _ConfirmarEliminacionDialogState
    extends State<ConfirmarEliminacionDialog> {
  // Tiempo de espera obligatorio.
  static const int duracionSegundos = 30;

  // Colores de StudyTrack.
  static const Color bordo = Color(0xFF670810);
  static const Color bordoSuave = Color(0xFF965E66);

  final TextEditingController _correoController = TextEditingController();

  final TextEditingController _palabraController = TextEditingController();

  Timer? _temporizador;

  int _segundosRestantes = duracionSegundos;

  String _t(String es, String pt) {
    return widget.portugues ? pt : es;
  }

  // =====================================================
  // MOSTRAR SOLO EL DOMINIO DEL CORREO
  // =====================================================

  String get _correoOculto {
    final partes = widget.correo.split('@');
    if (partes.length != 2) return '********';
    return "${'*' * partes[0].length}@${partes[1]}";
  }

  // =====================================================
  // VALIDACIONES
  // =====================================================

  bool get _correoCorrecto {
    return _correoController.text.trim().toLowerCase() ==
        widget.correo.trim().toLowerCase();
  }

  // Es obligatorio escribir ELIMINAR exactamente
  // en mayúsculas, sin espacios adicionales.
  bool get _palabraCorrecta {
    return _palabraController.text == 'ELIMINAR';
  }

  bool get _tiempoFinalizado {
    return _segundosRestantes == 0;
  }

  bool get _puedeConfirmar {
    return _correoCorrecto && _palabraCorrecta && _tiempoFinalizado;
  }

  // =====================================================
  // TEMPORIZADOR
  // =====================================================

  @override
  void initState() {
    super.initState();

    _temporizador = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_segundosRestantes <= 1) {
        timer.cancel();

        setState(() {
          _segundosRestantes = 0;
        });
      } else {
        setState(() {
          _segundosRestantes--;
        });
      }
    });
  }

  @override
  void dispose() {
    _temporizador?.cancel();

    _correoController.dispose();
    _palabraController.dispose();

    super.dispose();
  }

  // =====================================================
  // INTERFAZ
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;

    final fondoAviso = oscuro
        ? const Color(0xFF35292B)
        : const Color(0xFFFBF5F6);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: bordoSuave, size: 28),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              _t('Eliminar cuenta', 'Excluir conta'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),

      content: SizedBox(
        width: 430,

        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,

            children: [
              // =========================================
              // ADVERTENCIA
              // =========================================

              Container(
                padding: const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  color: fondoAviso,
                  borderRadius: BorderRadius.circular(12),
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      _t(
                        'Atención: esta acción es irreversible.',
                        'Atenção: esta ação é irreversível.',
                      ),

                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: bordoSuave,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      _t(
                        'Esta demostración elimina tu cuenta de acceso '
                            'de Firebase. Los datos académicos '
                            'de Supabase todavía no se eliminarán.',
                        'Esta demonstração exclui sua conta de acesso '
                            'do Firebase. Os dados acadêmicos '
                            'no Supabase ainda não serão excluídos.',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // =========================================
              // CONFIRMACIÓN DE CORREO
              // =========================================
              Text(
                _t(
                  '1. Confirmá tu correo electrónico',
                  '1. Confirme seu e-mail',
                ),

                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              SelectableText(
                _correoOculto,

                style: const TextStyle(fontWeight: FontWeight.w600),
              ),

              const SizedBox(height: 10),

              TextField(
                controller: _correoController,

                keyboardType: TextInputType.emailAddress,

                textCapitalization: TextCapitalization.none,

                autocorrect: false,

                onChanged: (_) {
                  setState(() {});
                },

                decoration: InputDecoration(
                  labelText: _t('Escribí tu correo', 'Digite seu e-mail'),

                  prefixIcon: const Icon(Icons.email_outlined),

                  border: const OutlineInputBorder(),

                  errorText:
                      _correoController.text.isNotEmpty && !_correoCorrecto
                      ? _t(
                          'El correo no coincide.',
                          'O e-mail não corresponde.',
                        )
                      : null,
                ),
              ),

              const SizedBox(height: 24),

              // =========================================
              // PALABRA DE CONFIRMACIÓN
              // =========================================
              Text(
                _t(
                  '2. Escribí exactamente ELIMINAR',
                  '2. Digite exatamente ELIMINAR',
                ),

                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              Text(
                _t(
                  'Debés utilizar todas las letras '
                      'en mayúsculas.',
                  'Você deve utilizar todas as letras '
                      'em maiúsculas.',
                ),
              ),

              const SizedBox(height: 10),

              TextField(
                controller: _palabraController,

                textCapitalization: TextCapitalization.none,

                autocorrect: false,
                enableSuggestions: false,

                onChanged: (_) {
                  setState(() {});
                },

                decoration: InputDecoration(
                  hintText: 'ELIMINAR',

                  prefixIcon: const Icon(Icons.edit_note_outlined),

                  border: const OutlineInputBorder(),

                  errorText:
                      _palabraController.text.isNotEmpty && !_palabraCorrecta
                      ? _t(
                          'Escribí ELIMINAR en mayúsculas.',
                          'Digite ELIMINAR em maiúsculas.',
                        )
                      : null,
                ),
              ),

              const SizedBox(height: 24),

              // =========================================
              // CUENTA REGRESIVA
              // =========================================
              Container(
                padding: const EdgeInsets.all(18),

                decoration: BoxDecoration(
                  color: fondoAviso,

                  borderRadius: BorderRadius.circular(12),
                ),

                child: Column(
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      color: bordoSuave,
                      size: 30,
                    ),

                    const SizedBox(height: 8),

                    Text(
                      '00:${_segundosRestantes.toString().padLeft(2, '0')}',

                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 12),

                    LinearProgressIndicator(
                      value:
                          (duracionSegundos - _segundosRestantes) /
                          duracionSegundos,

                      color: bordo,

                      minHeight: 6,
                    ),

                    const SizedBox(height: 12),

                    Text(
                      _tiempoFinalizado
                          ? _t(
                              'Tiempo de espera completado.',
                              'Tempo de espera concluído.',
                            )
                          : _t(
                              'Esperá antes de continuar.',
                              'Aguarde antes de continuar.',
                            ),

                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // =========================================
              // ACLARACIÓN DE DEMOSTRACIÓN
              // =========================================
              Text(
                _t(
                  'Atención: la cuenta de Firebase se eliminará '
                      'realmente. Usá solamente un usuario de prueba.',
                  'Atenção: a conta do Firebase será excluída '
                      'de verdade. Use apenas um usuário de teste.',
                ),

                textAlign: TextAlign.center,

                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),

      // =================================================
      // BOTONES
      // =================================================
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false);
          },

          child: Text(_t('Cancelar', 'Cancelar')),
        ),

        FilledButton.icon(
          // Solo se habilita si las tres condiciones
          // de confirmación están correctas.
          onPressed: _puedeConfirmar
              ? () {
                  Navigator.of(context).pop(true);
                }
              : null,

          style: FilledButton.styleFrom(
            backgroundColor: bordo,
            foregroundColor: Colors.white,
          ),

          icon: const Icon(Icons.delete_forever_outlined),

          label: Text(_t('Confirmar eliminación', 'Confirmar exclusão')),
        ),
      ],
    );
  }
}
