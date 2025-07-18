async function cargarCSV() {
  const response = await fetch('data.csv');
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
}

function mostrarQR(id) {
  const qrContainer = document.getElementById('qr-container');
  qrContainer.innerHTML = '';

  const wrapper = document.createElement('div');
  wrapper.style.display = 'flex';
  wrapper.style.flexDirection = 'column';
  wrapper.style.alignItems = 'center';

  const qrDiv = document.createElement('div');
  wrapper.appendChild(qrDiv);

  const textoID = document.createElement('p');
  textoID.textContent = `ID: ${id}`;
  wrapper.appendChild(textoID);

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

  qrCode.append(qrDiv);
  qrContainer.appendChild(wrapper);
}

cargarCSV();
