let datosTabla = []; // Guardar los datos para usar en el filtrado

// Cargar el CSV y llenar la tabla
async function cargarCSV() {
  const response = await fetch('data.csv?' + new Date().getTime());
  const data = await response.text();
  const filas = data.trim().split('\n');
  const cuerpo = document.querySelector('#tabla tbody');

  cuerpo.innerHTML = '';
  datosTabla = filas.slice(1).map(linea => linea.split(','));

  mostrarFilas(datosTabla);

  // Ocultar el botón "Descargar QR" al cargar
  document.getElementById('btnDescargar').style.display = 'none';
}

// Mostrar filas filtradas y sumar "Cantidad"
function mostrarFilas(filas) {
  const cuerpo = document.querySelector('#tabla tbody');
  cuerpo.innerHTML = '';

  let sumaCantidad = 0;

  filas.forEach(columnas => {
    const fila = document.createElement('tr');

    columnas.forEach((col, index) => {
      const celda = document.createElement('td');
      celda.textContent = col;
      fila.appendChild(celda);

      if (index === 2) {
        sumaCantidad += parseFloat(col) || 0;
      }
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

  // Agregar fila de total
  const filaTotal = document.createElement('tr');
  const numColumnas = filas[0]?.length || 0;

  for (let i = 0; i <= numColumnas; i++) {
    const celda = document.createElement('td');
    if (i === 1) {
      celda.textContent = 'Total';
      celda.style.fontWeight = 'bold';
    } else if (i === 2) {
      celda.textContent = sumaCantidad;
      celda.style.fontWeight = 'bold';
    } else {
      celda.textContent = '';
    }
    filaTotal.appendChild(celda);
  }

  filaTotal.style.backgroundColor = '#f0f8ff';
  cuerpo.appendChild(filaTotal);
}

// Mostrar QR y habilitar botón de descarga
function mostrarQR(id) {
  const qrContainer = document.getElementById('qr-container');
  const qrCodeDiv = document.getElementById('qr-code');
  const qrId = document.getElementById('qr-id');
  const btnDescargar = document.getElementById('btnDescargar');

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

  btnDescargar.style.display = 'inline-block';
  btnDescargar.onclick = () => {
    qrCode.download({ name: `QR_ID_${id}`, extension: "png" });
  };
}

// Buscador en tabla y oculta botón "Descargar QR"
document.getElementById('buscador').addEventListener('input', function () {
  const filtro = this.value.toLowerCase();

  const filtradas = datosTabla.filter(col =>
    col.join(',').toLowerCase().includes(filtro)
  );

  mostrarFilas(filtradas);

  document.getElementById('btnDescargar').style.display = 'none';
});

cargarCSV();
