<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>My AWS Portfolio - Image Upload</title>
    <style>
        body { font-family: sans-serif; display: flex; flex-direction: column; align-items: center; padding-top: 50px; background: #f4f7f6; }
        .card { background: white; padding: 2rem; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        button { background: #232f3e; color: white; border: none; padding: 10px 20px; border-radius: 4px; cursor: pointer; }
        button:disabled { background: #ccc; }
        #status { margin-top: 15px; font-weight: bold; }
    </style>
</head>
<body>

<div class="card">
    <h2>Cloud Image Uploader</h2>
    <input type="file" id="fileInput" accept="image/png,image/jpeg,image/gif,image/webp" />
    <button id="uploadBtn">Upload to AWS</button>
    <div id="status"></div>
</div>

<script>
    // Terraform replaces the placeholder below with the real API URL (templatefile).
    const API_URL = "${api_url}";
    const MAX_BYTES = 4 * 1024 * 1024; // keep in sync with the Lambda MAX_IMAGE_BYTES
    const uploadBtn = document.getElementById("uploadBtn");
    const statusDiv = document.getElementById("status");

    function show(text, color) {
        statusDiv.innerText = text;
        statusDiv.style.color = color;
    }

    uploadBtn.onclick = async () => {
        const file = document.getElementById("fileInput").files[0];
        if (!file) return alert("Please select a file first!");
        if (file.size > MAX_BYTES) return show("File is larger than 4 MB", "red");

        uploadBtn.disabled = true;
        show("Uploading to S3...", "blue");

        const reader = new FileReader();
        reader.readAsDataURL(file);

        reader.onload = async () => {
            // Strip the "data:image/png;base64," prefix, keep only the base64 part
            const base64 = reader.result.split(",")[1];

            try {
                const res = await fetch(API_URL, {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ image: base64, fileName: file.name, contentType: file.type })
                });
                const json = await res.json();

                if (!res.ok) throw new Error(json.error || "Server error");
                show("Success! Image saved. ID: " + json.imageId, "green");
            } catch (err) {
                console.error("Upload Error:", err);
                show("Upload failed: " + err.message, "red");
            } finally {
                uploadBtn.disabled = false;
            }
        };
    };
</script>
</body>
</html>
