import Testing
import Foundation
import AppKit
@testable import Alakeya

@Test
func browserToolNamesAreRegistered() {
    let names = Set(BrowserTools().toolNames)
    #expect(
        names.isSuperset(of: [
            "browser_open",
            "browser_read_page",
            "browser_click",
            "browser_type",
            "browser_back",
            "browser_reload",
            "browser_scroll",
            "browser_select",
            "browser_submit",
            "browser_wait",
            "browser_screenshot",
        ])
    )
}

@Test
func readPageIsLowRisk() {
    let action = BrowserTools().makeAction(
        toolName: "browser_read_page",
        args: [:]
    )
    #expect(action?.type == .browserReadPage)
    #expect(action?.risk == .low)
}

@Test
func clickAndTypeRequireConfirmationInAutoMode() {
    let click = BrowserTools().makeAction(
        toolName: "browser_click",
        args: ["text": "Продолжить"]
    )
    let type = BrowserTools().makeAction(
        toolName: "browser_type",
        args: ["field": "Поиск", "text": "Алакея"]
    )
    #expect(click?.risk == .medium)
    #expect(type?.risk == .medium)
}

@Test
func submitIsAlwaysHighRisk() {
    let action = BrowserTools().makeAction(
        toolName: "browser_submit",
        args: ["element_id": "ak-4"]
    )
    #expect(action?.risk == .high)
    #expect(PolicyEngine.shared.shouldAutoConfirm(action!) == false)
}

@Test
func passiveBrowserActionsAreLowRisk() {
    for tool in ["browser_scroll", "browser_wait", "browser_screenshot"] {
        let action = BrowserTools().makeAction(toolName: tool, args: [:])
        #expect(action?.risk == .low)
    }
}

@Test @MainActor
func browserCanReadTypeAndClickByElementID() async throws {
    let store = BrowserStore()
    store.webView.loadHTMLString(
        """
        <html><body>
          <input aria-label="Поиск" value="">
          <button onclick="document.querySelector('h1').textContent='Готово'">Продолжить</button>
          <h1>Ожидание</h1>
        </body></html>
        """,
        baseURL: URL(string: "https://example.test")
    )
    try await Task.sleep(nanoseconds: 500_000_000)

    let firstPage = try await store.readPage()
    let root = try #require(
        JSONSerialization.jsonObject(with: Data(firstPage.utf8)) as? [String: Any]
    )
    let elements = try #require(root["elements"] as? [[String: Any]])
    let inputID = try #require(
        elements.first(where: { $0["tag"] as? String == "input" })?["id"] as? String
    )
    let buttonID = try #require(
        elements.first(where: { $0["tag"] as? String == "button" })?["id"] as? String
    )

    _ = try await store.type(text: "Алакея", elementID: inputID, field: "")
    _ = try await store.click(elementID: buttonID, text: "")
    let updatedPage = try await store.readPage()

    #expect(updatedPage.contains("Алакея"))
    #expect(updatedPage.contains("Готово"))
}

@Test @MainActor
func plainBusinessSearchUsesDeterministicPipeline() {
    #expect(ToolRunner.detectScope("Найди 20 салонов красоты в Севастополе") == .localBusinessResearch)
    #expect(ToolRunner.detectScope("Собери 15 стоматологий в Москве в CSV") == .localBusinessResearchThenExport)
}

@Test
func hotelSearchSurvivesCityFollowUp() throws {
    let initial = LocalBusinessQuery.parse(from: "привет найди 10 отелей")

    #expect(initial.category == "отели")
    #expect(initial.targetCount == 10)
    #expect(initial.city == nil)

    let city = try #require(LocalBusinessQuery.parseCityContinuation(from: "севастополь"))
    let resumed = initial.resolvingCity(city)

    #expect(resumed.category == "отели")
    #expect(resumed.targetCount == 10)
    #expect(resumed.city == "Севастополь")
}

@Test
func unrelatedCommandDoesNotBecomePendingCity() {
    #expect(LocalBusinessQuery.parseCityContinuation(from: "найди теперь рестораны") == nil)
    #expect(LocalBusinessQuery.parseCityContinuation(from: "стоп") == nil)
}

@Test
func businessCardWrapperAndPhoneArraysAreParsed() throws {
    let json = """
    {
      "url": "https://example.test",
      "count": 2,
      "cards": [
        {
          "name": "Салон Лилия",
          "phones": ["+7 978 123-45-67"],
          "ratings": ["4,9 ★"],
          "address": "ул. Ленина, 10",
          "website": "https://lilia.example"
        },
        {
          "name": "Студия Ника",
          "phones": ["8 (978) 555-44-33"],
          "address": "проспект Победы, 2",
          "website": ""
        }
      ]
    }
    """
    let leads = LocalBusinessExtractionNormalizer.parseBusinessCards(
        json,
        source: "Тест",
        sourceURL: "https://example.test",
        city: "Севастополь"
    )
    #expect(leads.count == 2)
    #expect(leads[0].phone == "+7 978 123-45-67")
    #expect(leads[0].notes.contains("4,9"))
}

@Test
func contactObjectIsParsedAsSingleLead() {
    let json = """
    {
      "name": "Салон Лилия",
      "address": "ул. Ленина, 10",
      "phones": ["+7 978 123-45-67"]
    }
    """
    let leads = LocalBusinessExtractionNormalizer.parseContactCards(
        json,
        source: "Тест",
        sourceURL: "https://example.test",
        city: "Севастополь"
    )
    #expect(leads.count == 1)
    #expect(leads.first?.phone == "+7 978 123-45-67")
}

@Test
func annotationAspectFitKeepsImageInsideCanvas() {
    let rect = AnnotationGeometry.aspectFitRect(
        imageSize: CGSize(width: 1600, height: 900),
        containerSize: CGSize(width: 600, height: 600)
    )
    #expect(rect.width == 600)
    #expect(rect.height == 337.5)
    #expect(rect.minY == 131.25)
}

@Test @MainActor
func screenshotImageCanBeCopiedAsPNG() throws {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 4,
        pixelsHigh: 4,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    let image = NSImage(size: NSSize(width: 4, height: 4))
    image.addRepresentation(bitmap)

    #expect(BrowserClipboard.copy(image))
    #expect(NSPasteboard.general.data(forType: .png) != nil)
}

@Test
func searchSourcesRequestEnoughResults() {
    let google = LocalBusinessSearchSource.googleSearch
        .url(category: "салоны красоты", city: "Севастополь")?
        .absoluteString ?? ""
    let yandex = LocalBusinessSearchSource.yandexSearch
        .url(category: "салоны красоты", city: "Севастополь")?
        .absoluteString ?? ""

    #expect(google.contains("num=20"))
    #expect(yandex.contains("numdoc=50"))
}
