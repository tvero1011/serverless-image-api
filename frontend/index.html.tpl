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
        .gallery-card { width: 640px; max-width: 90vw; margin-top: 1.5rem; }
        .gallery-header { display: flex; justify-content: space-between; align-items: center; }
        .gallery-header button { background: #666; padding: 6px 14px; font-size: 0.9rem; }
        #gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); gap: 12px; margin-top: 1rem; }
        .thumb { display: flex; flex-direction: column; align-items: center; font-size: 0.75rem; color: #444; }
        .thumb img { width: 100%; aspect-ratio: 1; object-fit: cover; border-radius: 4px; border: 1px solid #ddd; }
        .thumb span { margin-top: 4px; max-width: 120px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        #galleryStatus { font-size: 0.85rem; color: #777; margin-top: 0.5rem; }
    </style>
</head>
<body>

<div class="card">
    <h2>Cloud Image Uploader</h2>
    <input type="file" id="fileInput" accept="image/png,image/jpeg,image/gif,image/webp" />
    <button id="uploadBtn">Upload to AWS</button>
    <div id="status"></div>
</div>

<div class="card gallery-card">
    <div class="gallery-header">
        <h2>Gallery</h2>
        <button id="refreshBtn">Refresh</button>
    </div>
    <div id="gallery"></div>
    <div id="galleryStatus"></div>
</div>

<script>
    // Terraform replaces the placeholders below with the real API URLs (templatefile).
    const API_URL = "${api_url}";
    const LIST_IMAGES_URL = "${list_images_url}";
    const MAX_BYTES = 4 * 1024 * 1024; // keep in sync with the Lambda MAX_IMAGE_BYTES
    const uploadBtn = document.getElementById("uploadBtn");
    const statusDiv = document.getElementById("status");
    const refreshBtn = document.getElementById("refreshBtn");
    const galleryDiv = document.getElementById("gallery");
    const galleryStatusDiv = document.getElementById("galleryStatus");

    function show(text, color) {
        statusDiv.innerText = text;
        statusDiv.style.color = color;
    }

    function escapeHtml(str) {
        const div = document.createElement("div");
        div.innerText = str;
        return div.innerHTML;
    }

    async function loadGallery() {
        galleryStatusDiv.innerText = "Loading...";
        try {
            // GET /images is a "simple" CORS request (no custom headers, no body),
            // so unlike the upload POST it never triggers a preflight OPTIONS call.
            const res = await fetch(LIST_IMAGES_URL + "?limit=24");
            const json = await res.json();
            if (!res.ok) throw new Error(json.error || "Server error");

            galleryDiv.innerHTML = "";
            for (const img of json.images) {
                const el = document.createElement("div");
                el.className = "thumb";
                el.innerHTML =
                    '<img src="' + img.url + '" alt="' + escapeHtml(img.originalName) + '" loading="lazy" />' +
                    '<span title="' + escapeHtml(img.originalName) + '">' + escapeHtml(img.originalName) + '</span>';
                galleryDiv.appendChild(el);
            }
            galleryStatusDiv.innerText = json.images.length
                ? json.images.length + " image(s). Thumbnail links expire after 5 minutes -- hit Refresh if one breaks."
                : "No images yet. Upload one above!";
        } catch (err) {
            console.error("Gallery load error:", err);
            galleryStatusDiv.innerText = "Couldn't load gallery: " + err.message;
        }
    }

    refreshBtn.onclick = loadGallery;
    window.addEventListener("DOMContentLoaded", loadGallery);

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
                loadGallery();
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
