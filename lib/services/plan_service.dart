
import 'package:flutter/foundation.dart';

class PlanService {
  // false = Free, true = Premium
  static final ValueNotifier<bool> esPremium =
      ValueNotifier<bool>(false);

  static void activarPremium() {
    esPremium.value = true;
  }

  static void activarFree() {
    esPremium.value = false;
  }

  static bool get premiumActivo => esPremium.value;

  static const int limiteTareasFree = 5;

  static bool puedeCrearTarea(int cantidadActual) {
    return premiumActivo ||
        cantidadActual < limiteTareasFree;
  }

  static bool get alertasProximidadDisponibles =>
      premiumActivo;
}
