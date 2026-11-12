# Whiteboard

A whiteboard you draw on by sliding your finger across a Mac trackpad, with no clicking or dragging.

- **Glide drawing:** lower the pen (tap or press `D`), then just move your finger to draw.
- **Finger tracking (Mac app):** press `T` and the trackpad becomes the page. Each point on the trackpad matches a point on the board, so lifting your finger makes a space. Good for handwriting and maths.
- **Endless board:** scroll with two fingers, pinch to zoom, press `Enter` (in finger tracking) for a new line.
- Pen, eraser, 7 colors, brush sizes, dot, graph, ruled or plain paper, undo and redo, and saving the whole board as a PNG.

Press `?` in the app for all shortcuts.

## Run it

**In a browser:** open `index.html`. Glide drawing works; finger tracking needs the Mac app.

**As a Mac app:** run

```sh
./build-app.sh
```

This compiles a small native wrapper (`app/main.swift`, needs Xcode command-line tools), installs `Whiteboard.app` in `~/Applications` and adds it to the Dock. Run it again after changing `index.html`.

The version number lives in `VERSION`.
