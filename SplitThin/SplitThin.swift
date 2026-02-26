import Foundation

public enum SplitThinMain {
    public static func messages() -> [String] {
        [
            "SplitThin main"
        ]
    }

    public static func main() {
        messages().forEach { message in
            print(message)
        }
    }
}
