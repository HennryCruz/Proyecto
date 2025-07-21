// Cargar el CSV y llenar la tabla
async function cargarCSV() {
  const response = await fetch('data.csv?' + new Date().getTime());
  const data = await response.text();
  const filas = data.trim().split('\n');
  const cuerpo = document.querySelector('#tabla tbody');

  cuerpo.innerHTML = '';

  filas.slice(1).forEach(linea => {
    const columnas = linea.split(',');
    const fila = document.createElement('tr');

    columnas.forEach(col => {
      const celda = document.createElement('td');
      celda.textContent = col;
      fila.appendChild(celda);
    });

    const celdaQR = document.createElement('td');
    const botonQR = document.createElement('button');
    botonQR.textContent = 'Ver QR';
    botonQR.addEventListener('click', () => {
      mostrarQR(columnas[0]); // Solo el ID
    });
    celdaQR.appendChild(botonQR);
    fila.appendChild(celdaQR);

    cuerpo.appendChild(fila);
  });

  // Ocultar el botón "Descargar QR" al cargar
  document.getElementById('btnDescargar').style.display = 'none';
}

// Mostrar QR y habilitar botón de descarga
function mostrarQR(id) {
  const qrContainer = document.getElementById('qr-container');
  const qrCodeDiv = document.getElementById('qr-code');
  const qrId = document.getElementById('qr-id');
  const btnDescargar = document.getElementById('btnDescargar');

  // Limpiar y mostrar ID
  qrCodeDiv.innerHTML = '';
  qrId.textContent = `ID: ${id}`;

  const qrCode = new QRCodeStyling({
    width: 220,
    height: 220,
    type: "svg",
    data: `https://cilindros.netlify.app/detalle.html?id=${id}`,
    image: "titulo.png",
    imageOptions: {
      crossOrigin: "anonymous",
      margin: 5,
      imageSize: 0.3
    },
    dotsOptions: {
      color: "#000000",
      type: "square"
    },
    backgroundOptions: {
      color: "#ffffff"
    }
  });

  qrCode.append(qrCodeDiv);

  // Mostrar botón de descarga
  btnDescargar.style.display = 'inline-block';
  btnDescargar.onclick = () => {
    qrCode.download({ name: `QR_ID_${id}`, extension: "png" });
  };
}

// Buscador en tabla y oculta botón "Descargar QR"
document.getElementById('buscador').addEventListener('input', function () {
  const filtro = this.value.toLowerCase();
  const filas = document.querySelectorAll('#tabla tbody tr');

  filas.forEach(fila => {
    const texto = fila.textContent.toLowerCase();
    fila.style.display = texto.includes(filtro) ? '' : 'none';
  });

  // Ocultar botón de descarga al buscar
  document.getElementById('btnDescargar').style.display = 'none';
});

cargarCSV();
