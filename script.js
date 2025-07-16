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

let qrCodeGlobal = null;

function generarQR(columnas) {
  const etiquetas = [
    "ID", "Producto", "Cantidad", "Usuario", "Edificio",
    "Localización", "Número de Serie", "Fecha de Entrada", "Contrato"
  ];

  const info = columnas.map((valor, i) =>
    `${etiquetas[i]}: ${quitarAcentos(valor).replace(/\n/g, ' ').replace(/\r/g, '')}`
  ).join('\n');

  const qrContainer = document.getElementById('qr-container');
  qrContainer.innerHTML = '';

  const wrapper = document.createElement('div');
  wrapper.style.display = 'flex';
  wrapper.style.flexDirection = 'column';
  wrapper.style.alignItems = 'center';
  wrapper.style.justifyContent = 'center';

  const qrDiv = document.createElement('div');
  wrapper.appendChild(qrDiv);

  const idTexto = document.createElement('p');
  idTexto.textContent = `ID: ${columnas[0]}`;
  idTexto.style.marginTop = '10px';
  idTexto.style.fontWeight = 'bold';
  wrapper.appendChild(idTexto);

  const btnDescargar = document.createElement('button');
  btnDescargar.textContent = 'Descargar QR';
  btnDescargar.style.marginTop = '10px';
  btnDescargar.addEventListener('click', () => {
    if (qrCodeGlobal) {
      qrCodeGlobal.download({
        name: `QR_${columnas[0]}`,
        extension: "png"
      });
    }
  });
  wrapper.appendChild(btnDescargar);

  qrContainer.appendChild(wrapper);

  const qrCode = new QRCodeStyling({
    width: 200,
    height: 200,
    type: "svg",
    data: info,
    image: "titulo.png",
    imageOptions: {
      crossOrigin: "anonymous",
      margin: 5,
      imageSize: 0.3
    },
    dotsOptions: {
      color: "#000",
      type: "square"
    },
    backgroundOptions: {
      color: "#ffffff"
    }
  });

  qrCode.append(qrDiv);
  qrCodeGlobal = qrCode;
}

cargarCSV();
