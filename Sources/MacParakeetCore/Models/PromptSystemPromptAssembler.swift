import Foundation

public enum PromptSystemPromptAssembler {
    public static func assemble(
        promptContent: String,
        extraInstructions: String?,
        userNotes: String? = nil,
        transcript: String? = nil
    ) -> String {
        let renderedPrompt = PromptTemplateRenderer.render(
            promptContent,
            substitutions: [
                .userNotes: userNotes ?? "",
                .transcript: transcript ?? "",
            ]
        )

        guard let extraInstructions,
            extraInstructions.contains(where: { !$0.isWhitespace })
        else {
            return renderedPrompt
        }
        return renderedPrompt + "\n\n" + extraInstructions
    }
}
