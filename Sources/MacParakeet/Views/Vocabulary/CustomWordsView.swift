import SwiftUI
import MacParakeetCore
import MacParakeetViewModels

struct CustomWordsView: View {
    @Bindable var viewModel: CustomWordsViewModel
    var recognitionStatus: CustomVocabularyBoostingSupportPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var hoveredWordID: UUID?
    @FocusState private var wordFieldFocused: Bool
    @FocusState private var replacementFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SheetAutoFocusSuppressor()
                .frame(width: 0, height: 0)

            VocabSheetHeader(
                title: "Custom Words",
                subtitle: recognitionStatus.detail,
                onDone: { dismiss() }
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    ParakeetTextField(
                        placeholder: "Search words…",
                        text: $viewModel.searchText,
                        leadingSystemImage: "magnifyingglass",
                        showsClearButton: true
                    )

                    recognitionSection
                    wordsSection
                    addSection
                }
                .padding(DesignSystem.Spacing.lg)
            }
        }
        .alert("Enable Vocabulary Hints?", isPresented: $viewModel.needsRecognitionConsent) {
            Button("Not Now") { Task { await viewModel.answerRecognitionConsent(false) } }
            Button("Download and Enable") { Task { await viewModel.answerRecognitionConsent(true) } }
        } message: {
            Text(
                "Download an additional local speech model to help Parakeet recognize your words. Audio and vocabulary stay on your Mac. Hints apply to new jobs, including Raw transcription; matching is not guaranteed."
            )
        }
        .alert(
            "Delete Word?",
            isPresented: Binding(
                get: { viewModel.pendingDeleteWord != nil },
                set: { if !$0 { viewModel.pendingDeleteWord = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeleteWord = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete()
            }
        } message: {
            if let word = viewModel.pendingDeleteWord {
                Text("Delete \"\(word.word)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Sections

    private var recognitionSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Toggle(
                "Vocabulary hints",
                isOn: Binding(
                    get: { viewModel.recognitionEnabled },
                    set: { enabled in Task { await viewModel.requestRecognitionEnabled(enabled) } }
                )
            )
            .parakeetSwitch()
            .disabled(viewModel.isPreparingRecognition)
            Text(recognitionStatus.title)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)
            if viewModel.isPreparingRecognition {
                ProgressView("Downloading and preparing vocabulary model…")
                    .controlSize(.small)
            }
            if let warning = viewModel.vocabularyWarning {
                Text(warning).font(DesignSystem.Typography.caption).foregroundStyle(.orange)
            }
            Text("English · Parakeet v2/v3 · Up to 100 enabled terms · At least 3 characters")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var wordsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            VocabSectionHeader(title: "Saved Words and Replacements") {
                Text(wordsCountLabel)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if viewModel.filteredWords.isEmpty {
                emptyWordsState
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.xl)
                    .vocabGroup()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredWords.enumerated()), id: \.element.id) { index, word in
                        if index > 0 {
                            Divider().padding(.leading, VocabMetrics.rowDividerInset)
                        }
                        wordRow(word)
                    }
                }
                .vocabGroup()
            }
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            VocabSectionHeader(
                title: viewModel.isReplacementEntry ? "Add Replacement" : "Add Vocabulary Word",
                subtitle: viewModel.isReplacementEntry
                    ? "Replace matching text after recognition in Clean mode."
                    : "Add a name or term you commonly say. No incorrect spelling is needed."
            )

            Picker("Entry type", selection: $viewModel.isReplacementEntry) {
                Text("Vocabulary words").tag(false)
                Text("Replacements").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.isReplacementEntry) { _, _ in viewModel.newReplacement = "" }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.errorRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                ParakeetTextField(
                    placeholder: "Word or phrase",
                    text: $viewModel.newWord,
                    onSubmit: {
                        if viewModel.isReplacementEntry { replacementFieldFocused = true } else { attemptAdd() }
                    },
                    externalFocus: $wordFieldFocused
                )
                if viewModel.isReplacementEntry {
                    ParakeetTextField(
                        placeholder: "Replacement",
                        text: $viewModel.newReplacement,
                        onSubmit: attemptAdd,
                        externalFocus: $replacementFieldFocused
                    )
                }
                Button("Add", action: attemptAdd)
                    .parakeetAction(.primaryProminent)
                    .controlSize(.large)
                    .disabled(viewModel.newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !viewModel.newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rulePreview
                    .transition(.opacity)
            }
        }
        .animation(DesignSystem.Animation.hoverTransition, value: viewModel.newWord.isEmpty)
    }

    @ViewBuilder
    private var rulePreview: some View {
        let word = viewModel.newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = viewModel.newReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        HStack(spacing: DesignSystem.Spacing.xs) {
            if replacement.isEmpty {
                Text("“\(word)”")
                    .font(DesignSystem.Typography.caption.monospaced())
                    .foregroundStyle(.primary)
                Text("recognition hint — not a guaranteed match")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("“\(word)”")
                    .font(DesignSystem.Typography.caption.monospaced())
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text("“\(replacement)”")
                    .font(DesignSystem.Typography.caption.monospaced())
                    .foregroundStyle(.primary)
            }
        }
        .padding(.leading, 2)
    }

    // MARK: - Rows

    private func wordRow(_ word: CustomWord) -> some View {
        let isHovered = hoveredWordID == word.id
        let trimmedReplacement = word.replacement?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let toggleHint: String =
            trimmedReplacement.isEmpty
            ? "Suggests this word during supported recognition"
            : "Replaces with \(trimmedReplacement)"
        return HStack(spacing: DesignSystem.Spacing.md) {
            Toggle(
                "",
                isOn: Binding(
                    get: { word.isEnabled },
                    set: { _ in viewModel.toggleEnabled(word) }
                )
            )
            .labelsHidden()
            .parakeetSwitch()
            .controlSize(.small)
            .accessibilityLabel("Enable \(word.word)")
            .accessibilityHint(toggleHint)

            VStack(alignment: .leading, spacing: 3) {
                Text(word.word)
                    .font(DesignSystem.Typography.body)
                    .opacity(word.isEnabled ? 1.0 : 0.55)

                if !trimmedReplacement.isEmpty {
                    Text("Replaces with: \(trimmedReplacement)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(word.word.count < 3 ? "Too short for recognition hints" : "Vocabulary word")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: DesignSystem.Spacing.sm)

            DeleteIconButton(
                helpText: "Delete \(word.word)",
                accessibilityName: "Delete \(word.word)"
            ) {
                viewModel.pendingDeleteWord = word
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm + 2)
        .background(isHovered ? DesignSystem.Colors.rowHoverBackground : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.hoverTransition) {
                hoveredWordID = hovering ? word.id : nil
            }
        }
    }

    private var emptyWordsState: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "character.textbox")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(viewModel.words.isEmpty ? "No custom words yet" : "No matches")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(.secondary)
            if viewModel.words.isEmpty {
                Text("Add names and terms you commonly say, or create explicit replacement rules.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                Button("Add Your First Word") {
                    wordFieldFocused = true
                }
                .parakeetAction(.primary)
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Helpers

    private var wordsCountLabel: String {
        let total = viewModel.words.count
        let searching = !viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty
        if searching {
            return "\(viewModel.filteredWords.count) of \(total)"
        }
        let disabled = viewModel.words.filter { !$0.isEnabled }.count
        if disabled > 0 {
            return "\(total) · \(disabled) off"
        }
        return total == 1 ? "1 entry" : "\(total) entries"
    }

    private func attemptAdd() {
        guard !viewModel.newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if viewModel.isReplacementEntry,
            viewModel.newReplacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            viewModel.errorMessage = "Enter replacement text. Use Vocabulary words for recognition hints."
            return
        }
        viewModel.addWord()
    }
}
