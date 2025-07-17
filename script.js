const etiquetas = ["ID", "Producto", "Cantidad", "Usuario", "Edificio", "Localización", "No° Serie", "Fecha de Entrada", "Contrato"];

fetch("data.csv")
  .then(response => response.text())
  .then(data => {
    const filas = data.trim().split("\n").slice(1); // Sin encabezado
    const cuerpoTabla = document.querySelector("#tabla tbody");

    filas.forEach(fila => {
      const columnas = fila.split(",");
      const tr = document.createElement("tr");

      columnas.forEach(col => {
        const td = document.createElement("td");
        td.textContent = col;
        tr.appendChild(td);
      });

      const botonQR = document.createElement("button");
      botonQR.textContent = "Generar QR";
      botonQR.onclick = () => generarQR(columnas);
      const tdQR = document.createElement("td");
      tdQR.appendChild(botonQR);
      tr.appendChild(tdQR);

      cuerpoTabla.appendChild(tr);
    });
  });

function generarQR(columnas) {
  const contenedorQR = document.getElementById("qr-container");
  contenedorQR.innerHTML = "";

  const id = columnas[0];
  const urlDinamica = `https://cilindros.netlify.app/detalle.html?id=${id}`;

  const qrCode = new QRCodeStyling({
    width: 200,
    height: 200,
    type: "svg",
    data: urlDinamica,
    image: "titulo.png", // opcional
    dotsOptions: { color: "#000", type: "rounded" },
    backgroundOptions: { color: "#fff" },
    imageOptions: { crossOrigin: "anonymous", margin: 10 }
  });

  const divQR = document.createElement("div");
  qrCode.append(divQR);
  contenedorQR.appendChild(divQR);

  const botonDescargar = document.createElement("button");
  botonDescargar.textContent = "Descargar QR";
  botonDescargar.onclick = () => qrCode.download({ name: `qr_${id}`, extension: "png" });
  contenedorQR.appendChild(botonDescargar);
}