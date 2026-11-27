import Testing
@testable import DailyFlowCore

@Suite("Auto-categorisation")
struct CategoriserTests {
    @Test(arguments: [
        ("Lecture notes", TaskCategory.uni),
        ("Revise for exam", .uni),
        ("Homework", .uni),
        ("Write up labs", .uni),
        ("Gym", .health),
        ("GYM!!", .health),
        ("Morning run", .health),
        ("Dentist check-up", .health),
        ("Update CV", .career),
        ("Job interview prep", .career),
        ("Pick up parcel", .errands),
        ("Buy groceries", .errands),
        ("Call the bank", .errands),
        ("Do the laundry", .home),
        ("Clean kitchen", .home),
        ("Dinner with friends", .social),
        ("Café catch up", .social),
        ("Something vague", .other),
        ("", .other),
        ("   ", .other)
    ])
    func guessesCategory(title: String, expected: TaskCategory) {
        #expect(TaskCategoriser.category(for: title) == expected)
    }

    @Test func longerPhrasesOutweighSingleWords() {
        // Home scores "cook" (1) + "cook dinner" (2) = 3.
        #expect(TaskCategoriser.category(for: "Cook dinner") == .home)
        // Social scores "dinner with" (2) + "friends" (1) + "family" (1) = 4, beating Home's 3.
        #expect(TaskCategoriser.category(for: "Cook dinner with friends and family") == .social)
        // A tie goes to the earlier category: Errands ("bank") before Social ("call").
        #expect(TaskCategoriser.category(for: "Call the bank") == .errands)
    }

    @Test func matchesWholeWordsOnly() {
        // "uni" must not match inside "unicorn", nor "work" inside "homework".
        #expect(TaskCategoriser.category(for: "Unicorn sticker") == .other)
        #expect(TaskCategoriser.category(for: "Homework") != .career)
    }
}
