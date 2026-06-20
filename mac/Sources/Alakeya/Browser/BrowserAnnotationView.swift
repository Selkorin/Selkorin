import SwiftUI
import AppKit

// ============================================================
// BrowserAnnotationView.swift
// Draws freehand strokes and rectangles on top of a browser
// screenshot, then exports the composite image to the clipboard.
// ============================================================

// ── Drawing model ──────────────────────────────────────────────

private enum AnnotationTool { case pen, rectangle }

private struct Stroke: Identifiable {
    let id = UUID()
    var points: [CGPoint] = []
    var rect: CGRect? = nil
    var color: Color
    var lineWidth: CGFloat
    var isPen: Bool
}

struct AnnotationGeometry {
    static func aspectFitRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let scale = min(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

// ── Main view ──────────────────────────────────────────────────

struct BrowserAnnotationView: View {
    let screenshot: NSImage
    let store: BrowserStore
    var onDismiss: () -> Void

    @State private var strokes: [Stroke] = []
    @State private var currentStroke: Stroke? = nil
    @State private var tool: AnnotationTool = .pen
    @State private var strokeColor: Color = Color(red: 0.35, green: 0.77, blue: 0.98)
    @State private var lineWidth: CGFloat = 3
    @State private var annotationCopied = false
    @State private var displayedImageSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(WAI.line)
            canvas
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(Color(hex: 0x09090F))
    }

    // ── Toolbar ───────────────────────────────────────────────

    private var toolbar: some View {
        HStack(spacing: 10) {
            // Tool buttons
            toolPick("Перо", systemImage: "pencil", t: .pen)
            toolPick("Прямоугольник", systemImage: "rectangle", t: .rectangle)

            Divider().frame(height: 20).background(WAI.line)

            // Color presets
            ForEach(colorPresets, id: \.1) { (label, color) in
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().stroke(
                            strokeColor == color ? Color.white : Color.clear,
                            lineWidth: 2
                        )
                    )
                    .onTapGesture { strokeColor = color }
                    .help(label)
            }

            Divider().frame(height: 20).background(WAI.line)

            // Line width
            Image(systemName: "line.diagonal")
                .font(.system(size: 10))
                .foregroundStyle(lineWidth < 3 ? WAI.accentBright : WAI.textFaint)
                .onTapGesture { lineWidth = 1.5 }
            Slider(value: $lineWidth, in: 1...12, step: 0.5)
                .frame(width: 70)
            Image(systemName: "line.diagonal")
                .font(.system(size: 16))
                .foregroundStyle(lineWidth > 4 ? WAI.accentBright : WAI.textFaint)
                .onTapGesture { lineWidth = 8 }

            Spacer()

            Button("Отменить") {
                if !strokes.isEmpty { strokes.removeLast() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(strokes.isEmpty ? WAI.textFaint : WAI.textDim)
            .disabled(strokes.isEmpty)
            .keyboardShortcut("z", modifiers: .command)

            Button("Очистить") { strokes = [] }
                .buttonStyle(.plain)
                .foregroundStyle(strokes.isEmpty ? WAI.textFaint : .orange)
                .disabled(strokes.isEmpty)

            Divider().frame(height: 20).background(WAI.line)

            Button("Отмена") { onDismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(WAI.textDim)
                .keyboardShortcut(.escape)

            Button(annotationCopied ? "Скопировано ✓" : "Готово") {
                exportAndCopy()
            }
            .buttonStyle(.plain)
            .foregroundStyle(annotationCopied ? WAI.success : WAI.accentBright)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: 0x111118))
    }

    private let colorPresets: [(String, Color)] = [
        ("Голубой",   Color(red: 0.35, green: 0.77, blue: 0.98)),
        ("Красный",   Color(red: 0.95, green: 0.30, blue: 0.30)),
        ("Жёлтый",   Color(red: 0.98, green: 0.85, blue: 0.20)),
        ("Зелёный",  Color(red: 0.30, green: 0.88, blue: 0.50)),
        ("Белый",    Color.white),
    ]

    private func toolPick(_ label: String, systemImage: String, t: AnnotationTool) -> some View {
        Button {
            tool = t
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(tool == t ? WAI.accentBright : WAI.textDim)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tool == t ? WAI.accentSoft : WAI.surfaceInset)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(tool == t ? WAI.lineAccent : WAI.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // ── Canvas ────────────────────────────────────────────────

    private var canvas: some View {
        GeometryReader { geo in
            let imageRect = AnnotationGeometry.aspectFitRect(
                imageSize: screenshot.size,
                containerSize: geo.size
            )
            ZStack {
                Image(nsImage: screenshot)
                    .resizable()
                    .frame(width: imageRect.width, height: imageRect.height)

                Canvas { ctx, size in
                    drawStrokes(strokes, in: ctx, size: size)
                }
                .frame(width: imageRect.width, height: imageRect.height)

                if let cs = currentStroke {
                    Canvas { ctx, size in
                        drawStrokes([cs], in: ctx, size: size)
                    }
                    .frame(width: imageRect.width, height: imageRect.height)
                }
            }
            .frame(width: imageRect.width, height: imageRect.height)
            .position(x: imageRect.midX, y: imageRect.midY)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        displayedImageSize = imageRect.size
                        handleDrag(value, size: imageRect.size)
                    }
                    .onEnded { _ in commitStroke() }
            )
            .cursor(.crosshair)
            .onAppear { displayedImageSize = imageRect.size }
            .onChange(of: geo.size) { _, _ in displayedImageSize = imageRect.size }
        }
    }

    private func handleDrag(_ value: DragGesture.Value, size: CGSize) {
        let pt = value.location
        if currentStroke == nil {
            currentStroke = Stroke(color: strokeColor, lineWidth: lineWidth, isPen: tool == .pen)
        }
        if tool == .pen {
            currentStroke?.points.append(pt)
        } else {
            // Rectangle: store start + current
            currentStroke?.points = [value.startLocation, pt]
            let minX = min(value.startLocation.x, pt.x)
            let minY = min(value.startLocation.y, pt.y)
            let w = abs(pt.x - value.startLocation.x)
            let h = abs(pt.y - value.startLocation.y)
            currentStroke?.rect = CGRect(x: minX, y: minY, width: w, height: h)
        }
    }

    private func commitStroke() {
        if let s = currentStroke, s.points.count > 0 || s.rect != nil {
            strokes.append(s)
        }
        currentStroke = nil
    }

    private func drawStrokes(_ list: [Stroke], in ctx: GraphicsContext, size: CGSize) {
        for stroke in list {
            ctx.stroke(
                makePath(stroke, size: size),
                with: .color(stroke.color),
                style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func makePath(_ stroke: Stroke, size: CGSize) -> Path {
        var path = Path()
        if stroke.isPen {
            guard stroke.points.count > 0 else { return path }
            path.move(to: stroke.points[0])
            for pt in stroke.points.dropFirst() {
                path.addLine(to: pt)
            }
        } else if let rect = stroke.rect {
            path.addRect(rect)
        }
        return path
    }

    // ── Export ────────────────────────────────────────────────

    private func exportAndCopy() {
        guard let exported = renderAnnotated() else { return }
        store.lastAnnotatedScreenshot = exported
        annotationCopied = BrowserClipboard.copy(exported)
        guard annotationCopied else { return }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            onDismiss()
        }
    }

    private func renderAnnotated() -> NSImage? {
        let imgSize = screenshot.size
        guard imgSize.width > 0, imgSize.height > 0,
              displayedImageSize.width > 0, displayedImageSize.height > 0 else { return nil }

        let result = NSImage(size: imgSize)
        result.lockFocus()
        defer { result.unlockFocus() }

        screenshot.draw(in: NSRect(origin: .zero, size: imgSize))

        let scaleX = imgSize.width / displayedImageSize.width
        let scaleY = imgSize.height / displayedImageSize.height
        let widthScale = (scaleX + scaleY) / 2

        for stroke in strokes {
            let path = NSBezierPath()
            path.lineWidth = stroke.lineWidth * widthScale
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor(stroke.color).setStroke()

            if stroke.isPen {
                guard stroke.points.count > 0 else { continue }
                path.move(to: NSPoint(
                    x: stroke.points[0].x * scaleX,
                    y: imgSize.height - stroke.points[0].y * scaleY
                ))
                for pt in stroke.points.dropFirst() {
                    path.line(to: NSPoint(
                        x: pt.x * scaleX,
                        y: imgSize.height - pt.y * scaleY
                    ))
                }
            } else if let rect = stroke.rect {
                let nsRect = NSRect(
                    x: rect.minX * scaleX,
                    y: imgSize.height - rect.maxY * scaleY,
                    width: rect.width * scaleX,
                    height: rect.height * scaleY
                )
                path.appendRect(nsRect)
            }
            path.stroke()
        }
        return result
    }
}

// ── Cursor helper ─────────────────────────────────────────────

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
