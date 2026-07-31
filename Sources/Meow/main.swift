import Foundation
import GeneratorCore

let includeDrafts = !CommandLine.arguments.contains("--publish")

let articlesDir = "Articles"
let decoder = JSONDecoder()

let allArticles: [Article] = {
    let files: [String]
    do {
        files = try FileManager.default.contentsOfDirectory(atPath: articlesDir).filter { $0.hasSuffix(".json") }
    } catch {
        print("Failed to read \(articlesDir): \(error)")
        exit(1)
    }
    var articles: [Article] = []
    for file in files {
        let path = "\(articlesDir)/\(file)"
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            articles.append(try decoder.decode(Article.self, from: data))
        } catch {
            print("Failed to parse \(path): \(error)")
            exit(1)
        }
    }
    // Filenames carry no ordering (slug, not reading order) — `number` is the source
    // of truth for the order articles appear in on the home page.
    return articles.sorted { $0.number < $1.number }
}()

let articles = publishableArticles(allArticles, includeDrafts: includeDrafts)

let brokenLinks = undefinedLinkSlugs(in: allArticles)
guard brokenLinks.isEmpty else {
    print("Broken article links — no article has these slugs: \(brokenLinks)")
    exit(1)
}

let links = linkTable(all: allArticles, published: articles)

func report(_ path: String, _ result: Result<Void, GeneratorError>) {
    switch result {
    case .success:
        print("Wrote \(path)")
    case .failure(let error):
        print("Failed to write \(path): \(error)")
    }
}

let tags = usedTags(in: articles)

report("dist/", prepareSite(at: "dist").runReader(.live))
report("dist/style.css", writeStylesheet(to: "dist/style.css").runReader(.live))
report("dist/fonts", writeFonts(into: "dist/fonts").runReader(.live))
report("dist/index.html", writeHomePage(articles, tags: tags, to: "dist/index.html").runReader(.live))

for article in articles {
    report("dist/articles/\(article.slug).html", writeArticle(article, into: "dist/articles", links: links, tags: tags).runReader(.live))
}

for tag in tags {
    report("dist/tags/\(tag.rawValue).html", writeTagPage(tag, articles: articles, tags: tags, into: "dist/tags").runReader(.live))
}
