import Foundation

public enum TaskCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case uni, health, career, errands, home, social, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .uni: "Uni"
        case .health: "Health"
        case .career: "Career"
        case .errands: "Errands"
        case .home: "Home"
        case .social: "Social"
        case .other: "Other"
        }
    }
}

/// Guesses a category from a task name by keyword matching. The owner can always override the guess.
///
/// Each matched keyword scores its word count, so "dinner with friends" (Social: "dinner with" + "friends")
/// beats "cook" style single words. Ties go to the earlier category in `TaskCategory.allCases`.
public enum TaskCategoriser {
    public static func category(for title: String) -> TaskCategory {
        let words = tokens(of: title)
        guard !words.isEmpty else { return .other }

        var best: (category: TaskCategory, score: Int) = (.other, 0)
        for category in TaskCategory.allCases where category != .other {
            let score = (keywords[category] ?? []).reduce(0) { total, phrase in
                let phraseWords = tokens(of: phrase)
                return total + (contains(words, phrase: phraseWords) ? phraseWords.count : 0)
            }
            if score > best.score {
                best = (category, score)
            }
        }
        return best.category
    }

    /// Lower-cased, accent-folded words.
    static func tokens(of text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// True when `phrase` appears as consecutive words. A single word also matches its simple plural.
    static func contains(_ words: [String], phrase: [String]) -> Bool {
        guard let firstWord = phrase.first, words.count >= phrase.count else { return false }
        if phrase.count == 1 {
            return words.contains { $0 == firstWord || $0 == firstWord + "s" || $0 == firstWord + "es" }
        }
        for start in 0...(words.count - phrase.count) where Array(words[start..<(start + phrase.count)]) == phrase {
            return true
        }
        return false
    }

    static let keywords: [TaskCategory: [String]] = [
        .uni: [
            "uni", "university", "campus", "lecture", "lecturer", "seminar", "tutorial", "essay", "assignment",
            "coursework", "dissertation", "thesis", "revision", "revise", "exam", "module", "lab", "homework",
            "study", "studying", "library", "reading list", "quiz", "timetable", "professor", "office hours"
        ],
        .health: [
            "gym", "workout", "run", "running", "jog", "jogging", "swim", "swimming", "yoga", "pilates", "stretch",
            "walk", "doctor", "gp", "dentist", "physio", "optician", "pharmacy", "prescription", "meds",
            "medication", "vitamins", "therapy", "hospital", "check up", "checkup", "blood test", "sleep",
            "meditate", "meditation"
        ],
        .career: [
            "cv", "resume", "cover letter", "interview", "job", "application", "apply", "internship", "placement",
            "linkedin", "portfolio", "networking", "recruiter", "career", "shift", "work", "meeting", "client",
            "timesheet", "onboarding"
        ],
        .errands: [
            "errand", "shop", "shopping", "groceries", "supermarket", "post office", "post", "parcel", "collect",
            "pick up", "drop off", "return", "buy", "order", "pay", "bank", "renew", "petrol", "fuel",
            "car wash", "mot", "haircut", "barber", "dry cleaning", "top up"
        ],
        .home: [
            "clean", "tidy", "hoover", "vacuum", "laundry", "washing", "ironing", "dishes", "bins", "recycling",
            "cook", "cook dinner", "meal prep", "garden", "plants", "water plants", "repair", "fix", "sheets",
            "change bed", "rent", "bills", "bathroom", "kitchen", "fridge", "declutter"
        ],
        .social: [
            "party", "birthday", "drinks", "pub", "brunch", "coffee with", "lunch with", "dinner with", "meet",
            "meet up", "catch up", "call", "facetime", "text", "friends", "family", "visit", "wedding", "gig",
            "concert", "cinema", "film night", "game night", "date night", "hang out"
        ]
    ]
}
