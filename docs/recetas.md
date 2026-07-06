# Recetas: paquetes de atajos por rubro

Bloques listos para pegar en tu `atajos.txt` (o en el gestor → **Importar IA**).
Cambia los datos de ejemplo por los tuyos. ¿Quieres un paquete a tu medida?
Usa [`PROMPT_PARA_IA.txt`](../PROMPT_PARA_IA.txt) con cualquier IA.

## 🛒 Ventas por WhatsApp

```ini
# ── Ventas ──
$yape=999 999 999 - Tu Nombre
saludo=Hola, buen día 😊\n¿En qué puedo ayudarte?
con[10|20|30|50]=Para confirmar tu pedido es necesario un adelanto de {1} soles.\n\nYape: {$yape}
pago=El pago es por Yape al {$yape} o por Plin al mismo número.
envio=El envío demora de 24 a 48 horas según tu distrito. Te paso el código de seguimiento apenas salga 📦
stock=¡Sí hay stock! ¿Te lo separo? Con tu adelanto queda reservado.
gracias!=¡Muchas gracias por tu compra! 🙌 Cualquier consulta me escribes.
```

## 🎓 Servicios académicos

```ini
# ── Académico ──
formato[apa:APA 7|ieee:IEEE|van:Vancouver][10:10 páginas|20:20 páginas|30:30 páginas]=Tu trabajo va en formato {1}, con una extensión de {2}. Incluye revisión de turnitin.
entrega=Tu trabajo estará listo el {fecha+7} como máximo. Te aviso apenas esté ✅
avance=Te envío el avance el {fecha+3} para que lo revises antes de continuar.
revision=Las revisiones están incluidas: me indicas los cambios y te lo devuelvo corregido en 24 h.
precio=El costo es S/ {cursor} e incluye revisiones y reporte de originalidad.
```

## 🏠 Inmobiliaria / alquileres

```ini
# ── Alquileres ──
requisitos=Para el alquiler se necesita:\n• DNI vigente\n• Último recibo de sueldo o RUC\n• 1 mes de garantía + 1 adelantado
visita=¡Claro! ¿Te parece una visita el {input:¿Qué día propones?} ? Confírmame la hora y te comparto la ubicación exacta.
dispo=Sigue disponible ✅ ¿Deseas agendar una visita?
```

## 🍔 Delivery / restaurante

```ini
# ── Delivery ──
carta=archivo:C:\negocio\carta.pdf
horario=Atendemos de lunes a sábado, 12:00 a 22:00. Domingos hasta las 20:00 🕗
demora=Tu pedido llega en 30-45 min aprox. ¡Gracias por la paciencia!
confirmar[efectivo|yape|tarjeta]=¡Pedido confirmado! Pago con {1} al recibir. Llega en 30-45 min 🛵
```

## 💼 Soporte / atención al cliente

```ini
# ── Soporte ──
recibido!=Recibido, lo reviso y te confirmo en breve.
ticket=Registré tu caso el {dia} {fecha} a las {hora}. Te respondo dentro del día.
solucion=Ya quedó resuelto ✅ Verifica por tu lado y me confirmas, por favor.
escala=Tu caso lo derivé al área encargada; te doy una respuesta a más tardar el {fecha+2}.
```

---

**Tips**
- Marca con `!` solo respuestas que nunca sean el inicio de otro atajo.
- Usa `{cursor}` donde va un dato que cambia cada vez (nombre, monto).
- Define tus datos repetidos como variables (`$yape=…`) y cámbialos en un solo lugar.
- Organiza con secciones `# ── Nombre ──`: el gestor las muestra y puedes guardar atajos nuevos directo en ellas.
