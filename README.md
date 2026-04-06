# Inventario CENAM — App Android

Migración del sistema VB2008 (Symbol Barcode2) a Android.

## Qué hace la app

- Carga catálogos de **959 localizaciones** y **~19,000 activos** al arrancar (offline, sin red)
- Seleccionas localización con autocomplete (busca por clave o por descripción)
- Escaneas con la **cámara del celular** (ML Kit, compatible con la mayoría de códigos)
- O capturas manualmente (botón "Captura manual")
- Guarda en `ALM_Inventarios.txt` con el mismo formato que el sistema original:  
  `LOCALIZACION_CVEACTIVO_DD/MM/YYYY`
- Comparte el `.txt` por WhatsApp/email/USB desde el botón de compartir
- Contador de registros visible en todo momento

## Cómo compilar (sin instalar nada en tu PC)

### Paso 1 — Subir a GitHub

1. Crea cuenta en https://github.com (gratis)
2. Crea repositorio nuevo privado (New repository → Private)
3. Sube todos estos archivos manteniendo la estructura de carpetas

### Paso 2 — Compilar en Codemagic

1. Crea cuenta en https://codemagic.io (gratis, 500 min/mes)
2. Conecta tu cuenta de GitHub
3. Selecciona tu repositorio
4. Elige **Flutter App**
5. En la configuración:
   - Build for: **Android**
   - Flutter version: **3.x (latest stable)**
   - Build mode: **Debug** (para prueba) o **Release**
6. Click **Start new build**
7. En ~10 minutos descarga el **APK** listo para instalar

### Paso 3 — Instalar en el celular

1. Descarga el APK a tu celular
2. En Android: Ajustes → Seguridad → **Fuentes desconocidas** (activar)
3. Abre el APK descargado → Instalar

## Dónde queda el archivo de inventario

El archivo `.txt` se guarda en:
```
/storage/emulated/0/Android/data/mx.gob.cenam.inventario/files/ALM_Inventario/ALM_Inventarios.txt
```

Para pasarlo a la PC:
- Usa el botón **Compartir** en la app (WhatsApp, email, etc.)
- O conecta el celular por USB y navega a esa carpeta

## Estructura del proyecto

```
inventario_cenam/
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── screens/
│   │   └── inventario_screen.dart
│   ├── services/
│   │   ├── catalogo_service.dart
│   │   └── inventario_service.dart
│   └── widgets/
│       └── manual_entry_dialog.dart
├── assets/
│   ├── localizaciones.txt   (959 localizaciones CENAM)
│   └── activos.txt          (~19,000 activos CENAM)
└── android/
    ├── app/
    │   ├── build.gradle
    │   └── src/main/
    │       ├── AndroidManifest.xml
    │       └── kotlin/mx/gob/cenam/inventario/
    │           └── MainActivity.kt
    ├── build.gradle
    ├── settings.gradle
    └── gradle.properties
```

## Dependencias Flutter usadas

| Paquete | Función |
|---|---|
| mobile_scanner | Lector de códigos de barras por cámara |
| path_provider | Acceso al almacenamiento del dispositivo |
| intl | Formato de fechas (dd/MM/yyyy) |
| share_plus | Compartir el archivo .txt |
