# app_distribuidora

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

# 📱 App Distribuidora

Aplicación móvil desarrollada en Flutter para la gestión de operaciones de una distribuidora.

Incluye módulos para:

* 🧑‍💼 Vendedores (rutas y visitas)
* 🚚 Choferes (entregas)
* 🏪 Bodega (picking)
* 👑 Admin (control y monitoreo)

---

# 🚀 🚀 Inicio rápido

```bash
cd app_distribuidora
flutter run -d chrome
```

---

# 🧪 Comandos Flutter

## Ejecutar app

```bash
flutter run -d chrome
```

## Verificar instalación

```bash
flutter doctor
```

## Crear proyecto

```bash
flutter create app_distribuidora
```

## Limpiar proyecto (cuando falla algo)

```bash
flutter clean
flutter pub get
flutter run -d chrome
```

## Hot reload (en ejecución)

Presionar:

```bash
r
```

---

# 📦 Dependencias

```bash
flutter pub get
```

```bash
flutter pub upgrade
```

---

# 🔁 Comandos Git (uso diario)

## Ver estado

```bash
git status
```

## Agregar cambios

```bash
git add .
```

## Crear commit

```bash
git commit -m "mensaje del cambio"
```

## Subir a GitHub

```bash
git push
```

---

# 🔗 Configuración inicial Git (solo primera vez)

```bash
git init
git add .
git commit -m "init proyecto flutter"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/app_distribuidora.git
git push -u origin main
```

---

# 🔄 Actualizar proyecto

```bash
git pull
```

---

# 📁 Estructura del proyecto

```text
lib/
 ├── core/
 ├── auth/
 ├── features/
 │    ├── admin/
 │    ├── vendedor/
 │    ├── chofer/
 │    ├── bodega/
 ├── shared/
```

---

# 🧠 Flujo de trabajo recomendado

1. Crear funcionalidad nueva
2. Probar con:

```bash
flutter run -d chrome
```

3. Guardar cambios:

```bash
git add .
git commit -m "nombre del avance"
git push
```

---

# ⚠️ Problemas comunes

## Flutter no reconocido

👉 Revisar PATH

## Error de dependencias

```bash
flutter clean
flutter pub get
```

## App no actualiza

👉 Presionar `r` en consola

---

# 📌 Notas

* El backend se encuentra en el ERP (API externa)
* Esta app consume endpoints (futuro):

  * /api/vendedor/visitas
  * /api/chofer/entregas
  * /api/bodega/picking

---

# 🚀 Roadmap

* [ ] Dashboard vendedor
* [ ] Ruta con visitas
* [ ] Registro de visitas
* [ ] GPS y validación
* [ ] Fotos
* [ ] Sincronización API

---

# 👨‍💻 Autor

Proyecto desarrollado por equipo interno La Quillotana
