// URL base de tu sitio en Netlify
const BASE_URL = "https://cilindros.netlify.app/detalle.html?id=";

document.addEventListener("DOMContentLoaded", async () => {
  const response = await fetch("data.csv?" + new Date().getTime());
  const data = await response.text();
  const filas = data.trim().split("\n").slice(1);
  const tabla = document.querySelector("#tabla tbody");

  filas.forEach(fila => {
    const columnas = fila.split(",");
    const tr = document.createElement("tr");

    columnas.forEach(col => {
      const td = document.createElement("td");
      td.textContent = col;
      tr.appendChild(td);
    });

    const botonTD = document.createElement("td");
    const boton = document.createElement("button");
    boton.textContent = "Ver QR";
    boton.addEventListener("click", () => generarQR(columnas[0])); // ID
    botonTD.appendChild(boton);
    tr.appendChild(botonTD);

    tabla.appendChild(tr);
  });
});

let qrCode; // global

function generarQR(id) {
  const qrDiv = document.getElementById("qr-container");
  qrDiv.innerHTML = ""; // Limpiar

  const url = `https://cilindros.netlify.app/detalle.html?id=${id}`;

  qrCode = new QRCodeStyling({
    width: 200,
    height: 200,
    type: "svg",
    data: url,
    image: "",
    dotsOptions: {
      color: "#000",
      type: "rounded"
    },
    backgroundOptions: {
      color: "#ffffff"
    }
  });

  qrCode.append(qrDiv);

  // Botón de descarga
  const botonDescarga = document.createElement("button");
  botonDescarga.textContent = "Descargar QR";
  botonDescarga.style.display = "block";
  botonDescarga.style.margin = "10px auto";
  botonDescarga.addEventListener("click", () => {
    qrCode.download({ name: `QR_${id}`, extension: "png" });
  });

  qrDiv.appendChild(botonDescarga);
}
