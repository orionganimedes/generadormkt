# Manual de Orquestación de Agentes: Proyecto NanoBanana Bot

Este documento define la arquitectura de trabajo colaborativo para el desarrollo, auditoría y despliegue del bot de Telegram. Para garantizar la calidad y el éxito del proyecto, el trabajo se ha dividido en cuatro roles o "Agentes" especializados.

## 👥 Perfiles y Responsabilidades de los Agentes

### 1. 🏗️ El Arquitecto (Diseño y Lógica Base)
**Rol:** Líder de Proyecto y Diseñador de Soluciones.
*   **Responsabilidades:**
    *   Definir la estructura de carpetas y la arquitectura general del sistema.
    *   Diseñar el flujo de datos entre Telegram, el backend en Python, OpenClaw y la API de OpenRouter.
    *   Traducir el "Manual de Identidad Gráfica" en *System Prompts* efectivos para la IA.
    *   Tomar decisiones sobre qué tecnologías y librerías usar.
*   **Entregables:** Documentos de arquitectura, diagramas de flujo y definición de requerimientos.

### 2. 🐍 Python (Desarrollador Backend)
**Rol:** Ingeniero de Software Principal.
*   **Responsabilidades:**
    *   Escribir el código fuente del proyecto (`bot.py`, `openrouter_service.py`, etc.).
    *   Implementar la lógica de negocio, manejo de imágenes (conversión a Base64) y peticiones HTTP.
    *   Gestionar el manejo de errores (try/except) y asegurar que el bot no se caiga ante fallos de la API.
    *   Seguir las mejores prácticas de programación orientada a objetos o funcional según defina el Arquitecto.
*   **Entregables:** Código fuente funcional, scripts de configuración y manejo de dependencias (`requirements.txt`).

### 3. 🛡️ DevGitAuditor (QA, Seguridad y Control de Versiones)
**Rol:** Revisor de Código y Gestor de Repositorio.
*   **Responsabilidades:**
    *   Auditar el código generado por *Python* buscando vulnerabilidades (ej. exposición de `.env`, inyecciones, fallos de memoria).
    *   Asegurar el cumplimiento de estándares de código (PEP8).
    *   Gestionar el flujo de Git: definir ramas (ej. `main`, `develop`, `feature/openrouter`), redactar mensajes de commit claros y manejar fusiones (merge).
    *   Crear y ejecutar pruebas (testing) para validar que el bot responde correctamente a las imágenes.
*   **Entregables:** Reportes de auditoría de código, historial de Git limpio y código optimizado.

### 4. 🚀 VPSGanímedes (Infraestructura y OpenClaw)
**Rol:** Ingeniero DevOps y Administrador de Sistemas.
*   **Responsabilidades:**
    *   Preparar el entorno de producción en el VPS (Linux/Ubuntu).
    *   Instalar y configurar **OpenClaw** como orquestador del entorno de ejecución.
    *   Configurar demonios o contenedores (systemd, Docker, PM2) para que el bot de Telegram se ejecute 24/7 de forma ininterrumpida.
    *   Gestionar variables de entorno seguras en el servidor, firewalls y monitoreo de recursos (CPU/RAM).
*   **Entregables:** Servidor aprovisionado, scripts de despliegue (bash), y el bot corriendo en producción.

---

## 🔄 Flujo de Trabajo (Pipeline de Orquestación)

Para implementar una nueva funcionalidad (por ejemplo, "Integrar el modelo Gemini Flash Image"), los agentes deben interactuar en el siguiente orden:

1.  **Fase de Diseño:** **El Arquitecto** analiza el requerimiento, define cómo se enviarán los datos a OpenRouter y documenta la estructura esperada.
2.  **Fase de Construcción:** **Python** toma las especificaciones del Arquitecto y programa los servicios y los handlers de Telegram en el entorno local.
3.  **Fase de Revisión:** **DevGitAuditor** revisa el código de *Python*, solicita correcciones si hay malas prácticas, y una vez aprobado, integra el código en la rama principal mediante Git.
4.  **Fase de Despliegue:** **VPSGanímedes** toma la versión aprobada por el auditor, la sube al VPS, configura OpenClaw y expone el servicio, asegurando que el bot esté en línea.

---

## 📡 Integración Específica con OpenClaw (Dominio de VPSGanímedes)

Dado que se utilizará **OpenClaw**, *VPSGanímedes* deberá asegurarse de:
*   Configurar los *workflows* dentro de OpenClaw para que actúen como intermediarios si es necesario escalar las peticiones.
*   Mantener el contexto de los agentes de OpenClaw sincronizado con los scripts de Python.
*   Monitorizar los logs del bot a través de las herramientas de observabilidad que provea el servidor.