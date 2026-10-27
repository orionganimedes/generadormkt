# Guía de Implementación Local: Bot de Telegram en Python (NanoBanana + Identidad Gráfica)

Este documento contiene la estructura de directorios y el código necesario para levantar el bot de Telegram de manera local utilizando Python, integrando la API de OpenRouter para generación de imágenes.

## 📁 Estructura del Proyecto

Crea una carpeta llamada `nanobanana_bot` y dentro de ella organiza los siguientes directorios y archivos:

```text
nanobanana_bot/
├── config/
│   └── settings.py          # Configuración de variables de entorno
├── services/
│   └── openrouter_service.py # Comunicación con OpenRouter e inyección del manual
├── bot.py                   # Script principal del bot de Telegram
├── requirements.txt         # Dependencias del proyecto
└── .env                     # Variables de entorno (no subir a GitHub)
```

## 💻 Código de los Archivos

### 1. `requirements.txt`
```text
python-telegram-bot==21.1.1
requests==2.31.0
python-dotenv==1.0.1
```

### 2. `config/settings.py`
```python
import os
from dotenv import load_dotenv

load_dotenv()

TELEGRAM_TOKEN = os.getenv("TELEGRAM_TOKEN", "")
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "")
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "google/gemini-2.5-flash-image")
```

### 3. `services/openrouter_service.py`
```python
import requests
import base64
from nanobanana_bot.config.settings import OPENROUTER_API_KEY, OPENROUTER_MODEL

def generate_flyer_with_openrouter(image_bytes: bytes, user_prompt: str) -> str:
    """
    Envía la imagen y el prompt a OpenRouter aplicando las reglas de identidad gráfica.
    """
    url = "https://openrouter.ai/api/v1/chat/completions"
    
    encoded_image = base64.b64encode(image_bytes).decode('utf-8')
    image_data_url = f"data:image/jpeg;base64,{encoded_image}"

    system_identity_prompt = (
        "Eres el Director de Arte oficial del movimiento. Tu objetivo es transformar la foto proporcionada "
        "en un flyer institucional profesional aplicando estrictamente el Manual de Identidad Gráfica: "
        "1. Usa obligatoriamente el rojo institucional (RGB: 179, 40, 45) y grises neutros. "
        "2. Incluye de forma nítida el logotipo oficial con la leyenda 'La esperanza de México', asegurando "
        "que NUNCA vaya ubicado en la parte inferior del diseño. "
        "3. Textos informativos centrados y limpios. "
        "4. Estética fotorrealista de alta calidad, respetando la dignidad de los escenarios comunitarios."
    )

    payload = {
        "model": OPENROUTER_MODEL,
        "messages": [
            {
                "role": "system",
                "content": system_identity_prompt
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": f"Instrucción específica del usuario: {user_prompt}"
                    },
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": image_data_url
                        }
                    }
                ]
            }
        ]
    }

    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/nanobanana",
        "X-Title": "NanoBanana Telegram Bot"
    }

    response = requests.post(url, json=payload, headers=headers)
    if response.status_code != 200:
        raise Exception(f"Error en OpenRouter API: {response.status_code} - {response.text}")
    
    result = response.json()
    try:
        message_content = result["choices"][0]["message"]["content"]
        return message_content
    except Exception as e:
        raise Exception(f"No se pudo extraer la respuesta: {str(e)}")
```

### 4. `bot.py`
```python
import os
import logging
from telegram import Update
from telegram.ext import ApplicationBuilder, ContextTypes, MessageHandler, filters, CommandHandler
from nanobanana_bot.config.settings import TELEGRAM_TOKEN
from nanobanana_bot.services.openrouter_service import generate_flyer_with_openrouter

logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO)
logger = logging.getLogger(__name__)

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "¡Bienvenido al Bot de Creación de Flyers con Identidad Gráfica!\n\n"
        "Envíame una fotografía junto con las instrucciones del evento para generar tu flyer."
    )

async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_caption = update.message.caption or "Genera un flyer institucional con esta imagen."
    await update.message.reply_text("🔄 Procesando imagen y aplicando manual de identidad...")

    try:
        photo_file = await update.message.photo[-1].get_file()
        image_bytes = await photo_file.download_as_bytearray()

        response_text = generate_flyer_with_openrouter(bytes(image_bytes), user_caption)
        
        await update.message.reply_text(f"✅ ¡Flyer generado con éxito!\n{response_text}")
    except Exception as e:
        logger.error(f"Error procesando la imagen: {e}")
        await update.message.reply_text(f"❌ Ocurrió un error: {str(e)}")

def main():
    if not TELEGRAM_TOKEN:
        print("Error: TELEGRAM_TOKEN no está configurado.")
        return

    app = ApplicationBuilder().token(TELEGRAM_TOKEN).build()

    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.PHOTO, handle_photo))

    print("🤖 Bot iniciado correctamente. Esperando mensajes...")
    app.run_polling()

if __name__ == '__main__':
    main()
```

## 🚀 Instrucciones de Ejecución

1. **Crear el entorno virtual (recomendado):**
   ```bash
   python -m venv venv
   source venv/bin/activate  # En Windows usa: venv\Scripts\activate
   ```

2. **Instalar dependencias:**
   ```bash
   pip install -r nanobanana_bot/requirements.txt
   ```

3. **Configurar credenciales:**
   Crea un archivo `.env` en la raíz del proyecto con tus tokens:
   ```env
   TELEGRAM_TOKEN=tu_token_de_botfather
   OPENROUTER_API_KEY=tu_api_key_de_openrouter
   ```

4. **Ejecutar el bot:**
   Asegúrate de estar en el directorio un nivel por encima de `nanobanana_bot` y ejecuta:
   ```bash
   python -m nanobanana_bot.bot
   ```