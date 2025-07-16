async function cargarCSV() {
  const response = await fetch('data.csv');
  const data = await response.text();
  const filas = data.trim().split('\n');
  const headers = filas[0].split(',');
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
      generarQR(columnas);
    });
    celdaQR.appendChild(botonQR);
    fila.appendChild(celdaQR);

    cuerpo.appendChild(fila);
  });
}

function quitarAcentos(texto) {
  return texto.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

function generarQR(columnas) {
  const etiquetas = [
    "ID", "Producto", "Cantidad", "Usuario", "Edificio",
    "Localización", "Número de Serie", "Fecha de Entrada", "Contrato"
  ];

  const info = columnas.map((valor, i) =>
    `${etiquetas[i]}: ${quitarAcentos(valor)}`
  ).join('\n');

  const qrContainer = document.getElementById('qr-container');
  qrContainer.innerHTML = '';

  const pre = document.createElement('pre');
  pre.textContent = info;
  qrContainer.appendChild(pre);

  const qrDiv = document.createElement('div');
  qrContainer.appendChild(qrDiv);

  const qrCode = new QRCodeStyling({
    width: 200,
    height: 200,
    type: "svg",
    data: info,
    dotsOptions: {
      color: "#000",
      type: "square"
    },
    backgroundOptions: {
      color: "#ffffff"
    }
  });

  qrCode.append(qrDiv);
}

cargarCSV();
