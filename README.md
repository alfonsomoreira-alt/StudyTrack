# 📚 StudyTrack

**Tu compañero académico: organiza materias, tareas, exámenes y tu rutina de estudio.**

StudyTrack es una aplicación desarrollada con **Flutter y Dart** para ayudar a los estudiantes a organizar su vida académica. El proyecto reúne autenticación, gestión de materias, tareas y exámenes, calendario, seguimiento de actividades, funciones de ubicación, lectura de códigos QR y notificaciones. Los datos académicos se almacenan en **Cloud Firestore** y se vinculan a la cuenta autenticada.

> **Estado del proyecto:** aplicación académica en desarrollo. Algunas integraciones y funciones demostrativas todavía requieren validación en un dispositivo físico. Las compras de planes son simuladas.

## 📑 Índice

- [Funcionalidades](#-funcionalidades)
- [Tecnologías](#-tecnologías)
- [Arquitectura y organización](#-arquitectura-y-organización)
- [Cómo ejecutar el proyecto](#-cómo-ejecutar-el-proyecto)
- [Generar e instalar el APK](#-generar-e-instalar-el-apk)
- [Notificaciones y permisos](#-notificaciones-y-permisos)
- [Rendimiento en computadoras con 8 GB de RAM](#-rendimiento-en-computadoras-con-8-gb-de-ram)
- [Capturas de pantalla](#-capturas-de-pantalla)
- [Limitaciones conocidas](#-limitaciones-conocidas)
- [Equipo y repositorio](#-equipo-y-repositorio)

## ✨ Funcionalidades

| Módulo | Funciones identificadas en el código |
| --- | --- |
| **Autenticación** | Registro, inicio de sesión, recuperación de contraseña y opción de acceso con Google mediante Firebase Authentication. |
| **Panel principal** | Resumen académico, acceso rápido a los módulos y seguimiento de tareas y próximas actividades. |
| **Materias** | Registro, edición, listado y eliminación; el repositorio incluye una protección contra la eliminación de materias con actividades asociadas. |
| **Tareas** | Creación, edición, eliminación, finalización, prioridades, fechas límite y recordatorios. Almacenamiento en Firestore. |
| **Calendario** | Visualización de actividades por fecha, incluidas tareas y exámenes. |
| **Exámenes** | Registro, edición, consulta y eliminación de evaluaciones. |
| **Perfil** | Datos personales y académicos, preferencias de idioma y apariencia. |
| **Idiomas** | Español y portugués de Brasil; la preferencia de idioma se guarda localmente. |
| **Tema** | Modos claro y oscuro, con preferencia persistente en el dispositivo. |
| **GPS y mapas** | Visualización de mapas, ubicación del dispositivo y lógica de alertas por proximidad. |
| **Código QR** | Lectura de códigos con la cámara del celular. |
| **Notificaciones** | Recordatorios locales en Android, historial en Firestore y configuración para recibir mensajes mediante Firebase Cloud Messaging. |
| **Reloj académico** | Interfaz simulada de tipo wearable para consultar tareas y plazos; no implica una integración comprobada con un reloj inteligente físico. |
| **Planes** | Interfaces Free, Pro y Premium de demostración. **No se identificó un sistema de cobro real en las pantallas examinadas.** |

### Idiomas y accesibilidad visual

La aplicación contiene archivos de localización para **español (`es`)**, **portugués (`pt`)** y **portugués de Brasil (`pt_BR`)**, además de temas claro y oscuro. Algunos mensajes de los servicios, como las notificaciones, se adaptan al idioma seleccionado.

## 🛠 Tecnologías

- **Flutter / Dart:** desarrollo de la interfaz y la lógica de la aplicación.
- **Firebase Authentication:** registro y autenticación de usuarios.
- **Cloud Firestore:** almacenamiento y sincronización de información académica e historial de notificaciones.
- **Firebase Cloud Messaging:** configuración para recibir mensajes en Android.
- **flutter_local_notifications:** recordatorios y notificaciones locales en Android.
- **flutter_map, geolocator y latlong2:** mapas y geolocalización.
- **mobile_scanner:** lectura de códigos QR.
- **shared_preferences:** almacenamiento local de preferencias.
- **intl y flutter_localizations:** internacionalización y formato de fechas.

Las versiones exactas de las dependencias se encuentran en `pubspec.yaml`.

## 🧱 Arquitectura y organización

Estructura principal identificada en los archivos del proyecto:

```text
StudyTrack/
├── android/                  # Configuración de la aplicación Android
├── assets/                   # Recursos visuales
├── lib/
│   ├── main.dart             # Inicio, tema, idioma y Firebase
│   ├── firebase_options.dart # Configuración del cliente Firebase
│   ├── theme_controller.dart # Preferencia del tema
│   ├── l10n/                 # Traducciones ES/PT
│   ├── screens/              # Pantallas y navegación
│   └── services/             # Repositorio, idioma, planes y notificaciones
├── pubspec.yaml              # Dependencias y configuración de Flutter
└── README.md
```

### Flujo de datos

1. El usuario se autentica mediante **Firebase Authentication**.
2. Los módulos académicos consultan y actualizan datos en **Cloud Firestore**.
3. El repositorio utiliza colecciones por usuario, por ejemplo:

```text
usuarios/{uid}
├── materias/
├── tarefas/
├── exames/
├── sesionesEstudio/
└── notificaciones/
```

4. Las preferencias de idioma y tema se guardan localmente.
5. En Android, el servicio de notificaciones puede programar recordatorios locales y registrar el historial en Firestore. Que un recordatorio figure como **programado** no confirma que el sistema operativo lo haya mostrado efectivamente.

> **Seguridad:** las reglas de Firestore deben restringir el acceso de cada usuario a sus propios documentos. La presencia de un `uid` en la ruta no reemplaza las reglas de seguridad correspondientes.

## 🚀 Cómo ejecutar el proyecto

### Requisitos previos

- Flutter SDK compatible con `pubspec.yaml` (el proyecto presentado declara **Dart `^3.9.2`**).
- Android Studio o VS Code con extensiones de Flutter y Dart.
- Android SDK, Java/JDK y herramientas de compilación configuradas.
- Proyecto Firebase configurado y acceso a la configuración Android correspondiente.
- Celular Android con depuración USB activada o emulador Android.

### 1. Clonar el repositorio

```bash
git clone https://github.com/alfonsomoreira-alt/StudyTrack.git
cd StudyTrack
```

### 2. Verificar el entorno e instalar dependencias

```bash
flutter doctor
flutter pub get
```

### 3. Revisar Firebase

Verifica la configuración en `lib/firebase_options.dart`, la configuración nativa de Android y los métodos de autenticación habilitados en Firebase. Antes de usar datos reales, el proyecto debe contar con reglas de seguridad adecuadas en Firestore.

> `firebase_options.dart` contiene identificadores de configuración del cliente Firebase. **No publiques** cuentas de servicio, contraseñas, tokens privados ni archivos con credenciales administrativas.

### 4. Ejecutar en Android

Conecta el celular por USB, permite la depuración y comprueba que aparezca entre los dispositivos:

```bash
flutter devices
flutter run
```

Si hay más de un dispositivo, utiliza el identificador mostrado por `flutter devices`:

```bash
flutter run -d ID_DEL_DISPOSITIVO
```

## 📱 Generar e instalar el APK

Para generar un archivo instalable en Android, ejecuta desde la carpeta principal del proyecto:

```bash
flutter pub get
flutter build apk --release
```

Si la compilación finaliza correctamente, el APK normalmente se crea en:

```text
build/app/outputs/flutter-apk/app-release.apk
```

**Instalación en el celular:** copia el archivo `.apk` al dispositivo Android, ábrelo y autoriza la instalación desde esa fuente si el sistema lo solicita. Como alternativa, con el celular conectado y ADB configurado:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

**Importante:** generar el APK no garantiza que todos los módulos funcionen correctamente. Prueba en el celular el inicio de sesión, la conexión con Firebase, los permisos de cámara y ubicación, el calendario, las tareas y las notificaciones. Para una distribución pública, configura la firma y publicación según el destino elegido.

## 🔔 Notificaciones y permisos

- **Android:** el servicio inicializa las notificaciones locales y solicita permisos cuando corresponde.
- **Recordatorios:** se programan según la zona horaria del dispositivo y `AndroidScheduleMode.inexactAllowWhileIdle`; el momento exacto de entrega puede variar.
- **Proximidad:** las alertas dependen de la ubicación y los permisos concedidos en Android.
- **Firebase Messaging:** la aplicación solicita permisos, obtiene un token cuando está disponible y procesa mensajes recibidos en primer plano. El envío dirigido y la navegación completa desde las notificaciones requieren configuración adicional.
- **Historial:** se almacena en `usuarios/{uid}/notificaciones` en Firestore.

Revisa los permisos necesarios en `AndroidManifest.xml` y prueba las funciones en un dispositivo físico.

## 💻 Rendimiento en computadoras con 8 GB de RAM

La compilación para Android utiliza memoria para Flutter, Gradle, Kotlin y Java. En equipos con **8 GB de RAM**, el proceso puede ser lento o presentar errores por falta de memoria.

### Recomendaciones prácticas

1. Cierra navegadores con muchas pestañas, emuladores y otros programas pesados durante la compilación.
2. **Utiliza preferentemente un celular físico conectado por USB** en lugar del emulador Android.
3. Mantén suficiente espacio libre en el disco para cachés, dependencias y archivos temporales.
4. Usa una sola instalación de Flutter y comprueba el SDK activo con `flutter --version`.
5. Si Gradle continúa sin memoria, revisa `android/gradle.properties` y ajusta los límites **según el error y la RAM disponible**. No aumentes `-Xmx` indiscriminadamente.
6. Si la compilación falló por problemas de caché, prueba `flutter clean` y `flutter pub get` antes de volver a compilar. Ten en cuenta que la siguiente compilación podría tardar más.

## 📸 Capturas de pantalla

Antes de la entrega final, agrega capturas **reales de la aplicación funcionando**, preferentemente en Android. Se recomienda esta organización:

```text
screenshots/
├── 01-login.png
├── 02-dashboard.png
├── 03-materias.png
├── 04-tareas.png
├── 05-calendario.png
├── 06-gps.png
└── 07-perfil.png
```

Una vez agregadas las imágenes al repositorio, reemplaza este aviso por una galería Markdown, por ejemplo:

```markdown
| Inicio de sesión | Panel principal | Tareas |
| --- | --- | --- |
| ![Inicio de sesión](screenshots/01-login.png) | ![Panel principal](screenshots/02-dashboard.png) | ![Tareas](screenshots/04-tareas.png) |
```

> No se proporcionaron capturas verificadas de la aplicación en funcionamiento para esta versión del README. Por ese motivo, no se presentan imágenes como si ya existieran.

## ⚠️ Limitaciones conocidas

- Los planes de pago son **demostrativos** y los cobros están simulados.
- El módulo wearable es una **simulación visual**; no se comprobó comunicación con un reloj inteligente físico.
- Algunas pantallas y textos del proyecto indican funciones **pendientes de integración**. Es necesario comprobar la navegación y su funcionamiento en la versión final.
- Las notificaciones locales descritas están orientadas a **Android**; su comportamiento puede variar en otras plataformas.
- La configuración de Firebase incluye opciones para distintas plataformas, que deben validarse individualmente antes de declarar compatibilidad completa con iOS, Web o escritorio.
- La compilación, las pruebas automatizadas y la instalación del APK **no se ejecutaron** durante la preparación de este documento.

## 👥 Equipo y repositorio

Proyecto académico desarrollado en equipo, con contribuciones a las pantallas, los servicios y la integración de la aplicación.

**Repositorio principal:** [alfonsomoreira-alt/StudyTrack](https://github.com/alfonsomoreira-alt/StudyTrack)

**Contribución de Nicolás Pivani:** desarrollo e integración de módulos de tareas, GPS y funciones relacionadas, según la distribución de trabajo comunicada. Las demás responsabilidades del equipo deben confirmarse antes de la publicación definitiva.

---

**StudyTrack: toda tu organización académica en un solo lugar.**
