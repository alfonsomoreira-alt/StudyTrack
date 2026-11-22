
import 'package:flutter/material.dart';
import '../services/plan_service.dart';

class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  static const Color bordo = Color(0xFF670310);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi plan'),
        backgroundColor: bordo,
        foregroundColor: Colors.white,
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: PlanService.esPremium,
        builder: (context, esPremium, _) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Icon(
                esPremium
                    ? Icons.workspace_premium
                    : Icons.person_outline,
                size: 75,
                color: bordo,
              ),
              const SizedBox(height: 16),
              Text(
                esPremium
                    ? 'Study Track Premium'
                    : 'Study Track Free',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                esPremium
                    ? '¡Todas las ventajas Premium están activadas!'
                    : 'Estás utilizando el plan gratuito.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              const Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.map),
                      title: Text('GPS y mapas'),
                      subtitle: Text('Disponible en ambos planes'),
                    ),
                    ListTile(
                      leading: Icon(Icons.task_alt),
                      title: Text('Tareas'),
                      subtitle: Text(
                        'Free: hasta 5 / Premium: ilimitadas',
                      ),
                    ),
                    ListTile(
                      leading: Icon(Icons.notifications_active),
                      title: Text('Alertas de proximidad'),
                      subtitle: Text('Exclusivas de Premium'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () {
                  if (esPremium) {
                    PlanService.activarFree();
                  } else {
                    PlanService.activarPremium();
                  }
                },
                icon: Icon(
                  esPremium
                      ? Icons.lock_open
                      : Icons.workspace_premium,
                ),
                label: Text(
                  esPremium
                      ? 'Volver al plan Free'
                      : 'Activar Premium (demo)',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: bordo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Modo demostración: no se realizan cobros reales.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          );
        },
      ),
    );
  }
}// Niklaus 
