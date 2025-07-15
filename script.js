async function cargarCSV() {
  const response = await fetch('data.csv');
  const data = await response.text();
  const filas = data.trim().split('\n');
  const headers = filas[0].split(',');
  const cuerpo = document.querySelector('#tabla tbody');

  // Limpia la tabla antes de agregar filas nuevas
  cuerpo.innerHTML = '';

  filas.slice(1).forEach(linea => {
    const columnas = linea.split(',');
    const fila = document.createElement('tr');

    columnas.forEach(col => {
      const celda = document.createElement('td');
      celda.textContent = col;
      fila.appendChild(celda);
    });

    // Botón para generar QR
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
  // Elimina QR e info anteriores si existen
  let contenedorQR = document.getElementById('qr-contenedor');
  if (contenedorQR) contenedorQR.remove();

  // Crear contenedor para QR e info
  contenedorQR = document.createElement('div');
  contenedorQR.id = 'qr-contenedor';
  contenedorQR.style.marginTop = '30px';
  document.body.appendChild(contenedorQR);

  const info = 
`ID: ${quitarAcentos(columnas[0])}
Producto: ${quitarAcentos(columnas[1])}
Cantidad: ${quitarAcentos(columnas[2])}
Usuario: ${quitarAcentos(columnas[3])}
Edificio: ${quitarAcentos(columnas[4])}
Localizacion: ${quitarAcentos(columnas[5])}`;

  // Mostrar texto
  const pre = document.createElement('pre');
  pre.textContent = info;
  contenedorQR.appendChild(pre);

  // Generar QR
  const qrDiv = document.createElement('div');
  contenedorQR.appendChild(qrDiv);

  new QRCode(qrDiv, {
    text: info,
    width: 128,
    height: 128,
  });
}

cargarCSV();
