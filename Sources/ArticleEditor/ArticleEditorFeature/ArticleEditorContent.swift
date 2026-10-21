import Localization
import AppDomain
import Foundation
import GeneratorCore
import SwiftUI
import Vitral
import VitralTokens
#if canImport(UIKit)
import UIKit
#endif

public struct ArticleEditorContent: View {
    let isDocumentOpen: Bool
    let title: Binding<String>
    let slug: Binding<String>
    let author: Binding<String>
    let emphasis: Binding<Emphasis>
    let draft: Binding<Bool>
    let number: Binding<Int>
    let published: Binding<PublicationDate?>
    let isPickingPublished: Binding<Bool>
    /// The publication date as it reads, written by the world.
    let publishedText: String
    let tags: [GeneratorCore.Tag]
    let allTags: [GeneratorCore.Tag]
    let brainstorming: Binding<String>
    let blocks: [EditableBlock]
    let allBlockKinds: [ContentBlockKind]
    let allSummaries: [ArticleSummary]
    let hasUnsavedChanges: Bool
    let isConfirmingRevert: Binding<Bool>
    let canUndo: Bool
    let canRedo: Bool
    let isSaving: Bool
    let saveError: LocalizedStringResource?
    let conflict: ExternalChangeState
    let isBuilding: Bool
    let buildStatus: LocalizedStringResource?
    let onToggleTag: (GeneratorCore.Tag) -> Void
    let onAddBlock: (ContentBlockKind, Int) -> Void
    let onRemoveBlock: (UUID) -> Void
    let onMoveBlocks: (IndexSet, Int) -> Void
    let onUpdateBlock: (UUID, ContentBlock) -> Void
    let onSave: () -> Void
    let onRequestRevert: () -> Void
    let onRevert: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onKeepMine: () -> Void
    let onReloadTheirs: () -> Void
    let onBuild: () -> Void
    let onRun: () -> Void
    let onOpenChat: () -> Void

    public var body: some View {
        // This screen only exists because an article was opened, so "nothing here" can
        // only ever mean "the file is still loading" — the "no article open" case belongs
        // to the detail column, which is where `AppRouter` now renders it.
        if !isDocumentOpen {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GlassList(backdrop: .grid(), rows: .padded) {
                if case .conflict = conflict {
                    conflictBanner
                }
                metadataSection
                brainstormingSection
                tagsSection
                blocksSection
            }
            .dropsFocusWhenScrolling()
            .navigationTitle(title.wrappedValue.isEmpty ? Text(L.Editor.untitled) : Text(verbatim: title.wrappedValue))
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                if let saveError {
                    Banner(Text(saveError), style: .error)
                        .padding(Space.small)
                }
            }
            .confirmationDialog(
                L.Editor.revertAllUnsavedChanges,
                isPresented: isConfirmingRevert,
                titleVisibility: .visible
            ) {
                Button(L.Editor.revertChanges, role: .destructive, action: onRevert)
                Button(L.Common.cancel, role: .cancel) {}
            } message: {
                Text(L.Editor.thisDiscardsEveryEditMade)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                onSave()
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Label(hasUnsavedChanges ? L.Editor.saveUnsaved : L.Common.save, systemImage: "square.and.arrow.down")
                }
            }
            .disabled(isSaving || !hasUnsavedChanges)
            .keyboardShortcut("s", modifiers: .command)
        }
        ToolbarItem(placement: .automatic) {
            Button(action: onUndo) {
                Label(L.Editor.undo, systemImage: "arrow.uturn.backward")
            }
            .disabled(!canUndo)
            .keyboardShortcut("z", modifiers: .command)
        }
        ToolbarItem(placement: .automatic) {
            Button(action: onRedo) {
                Label(L.Editor.redo, systemImage: "arrow.uturn.forward")
            }
            .disabled(!canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        ToolbarItem(placement: .automatic) {
            Button(role: .destructive, action: onRequestRevert) {
                // Distinct from Undo's icon on purpose — Revert jumps all the way back
                // to the last save in one shot, not one step back.
                Label(L.Editor.revertChanges, systemImage: "arrow.counterclockwise")
            }
            .disabled(!hasUnsavedChanges)
        }
        ToolbarItem(placement: .automatic) {
            Button {
                onBuild()
            } label: {
                if isBuilding {
                    ProgressView()
                } else {
                    Label(L.Editor.build, systemImage: "hammer")
                }
            }
            .disabled(isBuilding)
            .help(Text(buildStatus ?? L.Resource.Editor.generateTheFullSite))
            .keyboardShortcut("b", modifiers: .command)
        }
        ToolbarItem(placement: .automatic) {
            Button {
                onRun()
            } label: {
                Label(L.Editor.run, systemImage: "play.fill")
            }
            .disabled(!isDocumentOpen)
            .help(L.Editor.generateThisArticleAndOpen)
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    private var conflictBanner: some View {
        Section {
            Banner(L.Editor.thisFileChangedOnDisk, style: .warning)
                .trailing {
                    HStack(spacing: Space.small) {
                        ButtonSecondary(L.Editor.keepMine, size: .small, action: onKeepMine)
                        ButtonPrimary(L.Editor.reloadTheirs, size: .small, action: onReloadTheirs)
                    }
                }
        }
    }

    private var metadataSection: some View {
        Section(L.Editor.metadata) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.Common.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PasteAwareTextEditor(
                    text: title,
                    fontName: SiteTypography.headingFontName,
                    fontSize: SiteTypography.titleSize,
                    disablesNewlines: true,
                    isLinkAware: false
                )
            }
            FieldText(L.Editor.slug, text: slug)
            FieldText(L.Editor.author, text: author)
            SegmentedControlGlass(selection: emphasis, options: [
                ChoiceOption(Emphasis.text, title: L.Editor.text),
                ChoiceOption(Emphasis.video, title: L.Editor.video),
            ])
            .accessibilityLabel(Text(L.Editor.emphasis))
            ToggleSwitch(L.Editor.draft, isOn: draft)
            FieldStepper(L.Editor.number(number.wrappedValue), value: number, in: 0...999)
            publishedField
        }
    }

    private var publishedField: some View {
        let isPublished = Binding<Bool>(
            get: { published.wrappedValue != nil },
            set: { enabled in
                published.wrappedValue = enabled ? (published.wrappedValue ?? todayPublicationDate()) : nil
            }
        )
        return VStack(alignment: .leading) {
            ToggleSwitch(L.Editor.published, isOn: isPublished)
            if published.wrappedValue != nil {
                FieldDate(
                    L.Editor.date,
                    date: Binding<Date>(
                        get: { (published.wrappedValue ?? todayPublicationDate()).asDate },
                        set: { published.wrappedValue = PublicationDate(date: $0) }
                    ),
                    format: { _ in Text(verbatim: publishedText) },
                    isPicking: isPickingPublished
                )
            }
        }
    }

    private var tagsSection: some View {
        Section(L.Editor.tags) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sortedTags, id: \.self) { tag in
                        TagToggle(
                            LocalizedStringKey("#\(tag.rawValue)"),
                            isOn: Binding(get: { tags.contains(tag) }, set: { _ in onToggleTag(tag) })
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var sortedTags: [GeneratorCore.Tag] {
        allTags.sorted { $0.rawValue < $1.rawValue }
    }

    private var blocksSection: some View {
        Section(L.Editor.blocks) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                BlockRow(
                    block: block,
                    allSummaries: allSummaries,
                    allBlockKinds: allBlockKinds,
                    isFirst: index == 0,
                    isLast: index == blocks.count - 1,
                    onUpdate: { onUpdateBlock(block.id, $0) },
                    onRemove: { onRemoveBlock(block.id) },
                    onMoveUp: { onMoveBlocks(IndexSet(integer: index), max(index - 1, 0)) },
                    onMoveDown: { onMoveBlocks(IndexSet(integer: index), min(index + 2, blocks.count)) },
                    onAddBefore: { onAddBlock($0, index) },
                    onAddAfter: { onAddBlock($0, index + 1) }
                )
            }
            .onMove(perform: onMoveBlocks)
            .onDelete { offsets in
                for index in offsets { onRemoveBlock(blocks[index].id) }
            }

            Menu {
                ForEach(allBlockKinds) { kind in
                    Button(L.domain(kind.displayName)) { onAddBlock(kind, blocks.count) }
                }
            } label: {
                Label(L.Editor.addBlock, systemImage: "plus")
            }
        }
    }

    /// Personal notes, never rendered to the generated site — monospaced so pasted code
    /// snippets don't look confusing, but otherwise a plain text box: no syntax colour,
    /// no paste-aware link handling, no contextual menu.
    private var brainstormingSection: some View {
        // The assistant reads/writes THIS article's Brainstorming — so it's opened from
        // here, scoped to the article that's actually open, not from a top-level "app"
        // toolbar button unrelated to any particular article.
        Section {
            PasteAwareTextEditor(
                text: brainstorming,
                isMonospace: true,
                fontSize: SiteTypography.codeSize,
                isLinkAware: false
            )
        } header: {
            HStack {
                Text(L.Editor.brainstorming)
                Spacer()
                Button(action: onOpenChat) {
                    Label(L.Editor.askAssistant, systemImage: "apple.intelligence")
                }
                .buttonStyle(.plain)
                .font(.footnote)
            }
        }
    }
}

private func todayPublicationDate() -> PublicationDate {
    // A reasonable default when a user enables "Published" for the first time; they
    // are expected to adjust it, same as hand-typing a date when writing a new article.
    PublicationDate(year: 2026, month: 1, day: 1)
}

/// A fixed Gregorian/UTC calendar for `PublicationDate ⇄ Date` conversion — deliberately
/// not `Calendar.current` (which reads the device's locale/region), since a UTC calendar
/// makes the conversion a pure function of the y/m/d values, with no ambient dependency
/// and no timezone-driven date-shifting near midnight.
private let publicationDateCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
}()

private extension PublicationDate {
    /// For binding to `DatePicker`, which only speaks `Date`.
    var asDate: Date {
        publicationDateCalendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    init(date: Date) {
        let components = publicationDateCalendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }
}

private struct BlockRow: View {
    let block: EditableBlock
    let allSummaries: [ArticleSummary]
    let allBlockKinds: [ContentBlockKind]
    let isFirst: Bool
    let isLast: Bool
    let onUpdate: (ContentBlock) -> Void
    let onRemove: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onAddBefore: (ContentBlockKind) -> Void
    let onAddAfter: (ContentBlockKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kindLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                addBlockMenu(help: L.Editor.addBlockAbove, onAdd: onAddBefore)
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(isFirst)
                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(isLast)
                addBlockMenu(help: L.Editor.addBlockBelow, onAdd: onAddAfter)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            content
        }
        .padding(.vertical, 4)
    }

    private func addBlockMenu(help: LocalizedStringKey, onAdd: @escaping (ContentBlockKind) -> Void) -> some View {
        Menu {
            ForEach(allBlockKinds) { kind in
                Button(L.domain(kind.displayName)) { onAdd(kind) }
            }
        } label: {
            Image(systemName: "plus")
        }
        .help(help)
    }

    private var kindLabel: LocalizedStringKey {
        switch block.block {
        case .heading: L.Editor.heading
        case .paragraph: L.Editor.paragraph
        case .list: L.Editor.list
        case .image: L.Editor.image
        case .video: L.Editor.video
        case .code: L.Editor.code
        case .equation: L.Editor.equationReadOnly
        }
    }

    @ViewBuilder
    private var content: some View {
        switch block.block {
        case .heading(let level, let text):
            SegmentedControlGlass(
                selection: Binding(get: { level }, set: { onUpdate(.heading(level: $0, text: text)) }),
                options: [
                    ChoiceOption(HeadingLevel.section, title: L.Editor.section),
                    ChoiceOption(HeadingLevel.subsection, title: L.Editor.subsection),
                ]
            )
            .accessibilityLabel(Text(L.Editor.level))
            PasteAwareTextEditor(
                text: Binding(
                    get: { text },
                    set: { onUpdate(.heading(level: level, text: $0)) }
                ),
                fontName: SiteTypography.headingFontName,
                fontSize: level == .section ? SiteTypography.sectionHeadingSize : SiteTypography.subsectionHeadingSize,
                disablesNewlines: true,
                isLinkAware: false
            )

        case .paragraph(let text):
            PasteAwareTextEditor(
                text: Binding(
                    get: { text },
                    set: { onUpdate(.paragraph($0)) }
                ),
                allSummaries: allSummaries,
                disablesNewlines: true
            )

        case .list(let items, let bullet):
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                TextField(L.Editor.item(index + 1), text: Binding(
                    get: { item },
                    set: { newValue in
                        var newItems = items
                        newItems[index] = newValue
                        onUpdate(.list(items: newItems, bullet: bullet))
                    }
                ))
                .font(SiteTypography.body)
            }
            HStack {
                ButtonSecondary(L.Editor.addItem, size: .small) { onUpdate(.list(items: items + [""], bullet: bullet)) }
                if items.count > 1 {
                    ButtonSecondary(L.Editor.removeLast, size: .small) { onUpdate(.list(items: Array(items.dropLast()), bullet: bullet)) }
                }
            }
            FieldText(L.Editor.bulletOptionalEG, text: Binding(
                get: { bullet ?? "" },
                set: { onUpdate(.list(items: items, bullet: $0.isEmpty ? nil : $0)) }
            ))

        case .image(let url, let altText):
            FieldText(L.Editor.url, text: Binding(get: { url }, set: { onUpdate(.image(url: $0, altText: altText)) }))
            FieldText(L.Editor.altText, text: Binding(get: { altText }, set: { onUpdate(.image(url: url, altText: $0)) }))

        case .video(let url, let caption):
            FieldText(L.Editor.url, text: Binding(get: { url }, set: { onUpdate(.video(url: $0, caption: caption)) }))
            FieldText(L.Editor.captionOptional, text: Binding(
                get: { caption ?? "" },
                set: { onUpdate(.video(url: url, caption: $0.isEmpty ? nil : $0)) }
            ))

        case .code(let language, let source):
            PasteAwareTextEditor(
                text: Binding(get: { source }, set: { onUpdate(.code(language: language, source: $0)) }),
                isMonospace: true,
                isSyntaxHighlighted: true,
                fontSize: SiteTypography.codeSize,
                allSummaries: allSummaries,
                isLinkAware: false
            )

        case .equation:
            Text(L.Editor.equationBlocksArentEditableYet)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

}

private extension View {
    /// Gives up keyboard focus the moment a scroll starts — iOS and iPadOS only.
    ///
    /// A focused field is the first responder, and UIKit keeps bringing the first
    /// responder back into view on later layout passes. So editing one field and then
    /// scrolling away to read the rest of the article would yank the page back to that
    /// field once the scroll settled — and keep doing it for as long as that field stayed
    /// focused, which is forever unless something else happened to take it. Scrolling
    /// means reading rather than editing, so the scroll is what ends the edit.
    ///
    /// `scrollDismissesKeyboard` is the obvious modifier for this and does nothing here:
    /// it only has a keyboard to dismiss when the *software* keyboard is up, so on an iPad
    /// with a hardware keyboard — confirmed by typing after a scroll in Simulator and
    /// watching the text still land in the field left behind — focus simply stayed put.
    /// Asking the responder chain directly is what works with either keyboard, and it
    /// covers every field in the form at once: the `UITextView`s behind
    /// ``PasteAwareTextEditor`` and the plain SwiftUI `TextField`s alike, where a
    /// `FocusState` would have to enumerate them and still could not reach the
    /// representable-backed ones.
    ///
    /// Not applied on macOS: scrolling with a trackpad while the caret sits in a field is
    /// ordinary there, an `NSScrollView` never drags itself back to the first responder,
    /// and dropping focus mid-edit would be the surprising behaviour rather than the fix.
    func dropsFocusWhenScrolling() -> some View {
        #if os(macOS)
        self
        #else
        onScrollPhaseChange { _, phase in
            guard phase == .interacting else { return }
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        #endif
    }
}
