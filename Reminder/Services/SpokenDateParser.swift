import Foundation

/// 从一句口语里拆出日期、时间和事项内容，供 Siri 添加提醒使用。
/// 例："明天下午2点去洗车" → 明天 14:00，"去洗车"
/// 支持：今天/明天/后天/大后天、今晚/明早、N天后、N周后、(这|下|下下)周X、X月X号、X号、
///      上午/下午/晚上 + N点(半|一刻|三刻|N分)、14:30
struct SpokenDateParser {
    struct Result {
        var text: String
        /// nil 表示没说日期，作为常年提醒
        var dueDate: Date?
        var hasTime: Bool
    }

    private static let num = "[0-9零〇一二两三四五六七八九十]{1,4}"
    private static let period = "凌晨|早上|早晨|清早|上午|中午|下午|傍晚|晚上|夜里"

    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> Result {
        var s = input
        // 把"今晚""明早"之类拆成日期 + 时段，后面分别处理
        for (from, to) in [("今晚", "今天晚上"), ("今夜", "今天晚上"), ("今早", "今天早上"),
                           ("明晚", "明天晚上"), ("明早", "明天早上"), ("明晨", "明天早上")] {
            s = s.replacingOccurrences(of: from, with: to)
        }

        // "买一点水果""快一点"里的"一点"不是时间：前面没有时段、后面没有分钟的中文"一点"先藏起来
        let placeholder = "\u{E000}"
        if let regex = try? NSRegularExpression(pattern: "(?<!\(period))一点(?![半一二三四五六七八九十0-9点刻分])") {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: placeholder)
        }

        let today = calendar.startOfDay(for: now)
        var day: Date?

        // 1. 日期（只取第一个匹配到的说法）
        if let m = match(#"大后天|后天|明天|明日|明儿|今天|今日|今儿"#, in: &s) {
            let offset = ["大后天": 3, "后天": 2, "明天": 1, "明日": 1, "明儿": 1][m[0]] ?? 0
            day = calendar.date(byAdding: .day, value: offset, to: today)
        } else if let m = match("(\(num))\\s*(天|日|周|个?星期|个?礼拜|个月)(?:以后|之后|后)", in: &s),
                  let n = number(m[1]) {
            let unit = m[2]
            day = unit.hasSuffix("月")
                ? calendar.date(byAdding: .month, value: n, to: today)
                : calendar.date(byAdding: .day, value: unit == "天" || unit == "日" ? n : n * 7, to: today)
        } else if let m = match("(这|本|下下|下)?个?(?:周|星期|礼拜)([一二三四五六日天1-7])", in: &s),
                  let target = weekdayIndex(m[2]) {
            // 周一 = 0 … 周日 = 6
            let current = (calendar.component(.weekday, from: today) + 5) % 7
            let delta = switch m[1] {
            case "这", "本": target - current
            case "下": 7 - current + target
            case "下下": 14 - current + target
            default: (target - current + 7) % 7   // 没说哪一周：今天或之后最近的那天
            }
            day = calendar.date(byAdding: .day, value: delta, to: today)
        } else if let m = match("(?:(\(num))\\s*年)?\\s*(\(num))\\s*月\\s*(\(num))\\s*(?:日|号)?", in: &s),
                  let month = number(m[2]), let d = number(m[3]) {
            let explicitYear = number(m[1])
            var c = DateComponents(year: explicitYear ?? calendar.component(.year, from: today), month: month, day: d)
            if var date = calendar.date(from: c) {
                // 没说年份且日期已过，算明年
                if explicitYear == nil, date < today {
                    c.year! += 1
                    date = calendar.date(from: c) ?? date
                }
                day = date
            }
        } else if let m = match("(\(num))\\s*号", in: &s), let d = number(m[1]) {
            var c = calendar.dateComponents([.year, .month], from: today)
            c.day = d
            if var date = calendar.date(from: c) {
                // 本月已过，算下个月
                if date < today, let next = calendar.date(byAdding: .month, value: 1, to: date) { date = next }
                day = date
            }
        }

        // 2. 时间
        var hour: Int?
        var minute = 0
        if let m = match("(\(period))?\\s*(\(num))\\s*(?:点|时|[:：])\\s*(半|一刻|三刻|(\(num))\\s*分?)?", in: &s),
           let h = number(m[2]) {
            let p = m[1], extra = m[3]
            hour = adjust(hour: h, period: p)
            minute = switch extra {
            case "半": 30
            case "一刻": 15
            case "三刻": 45
            default: number(m[4]) ?? 0
            }
        }

        var result = finish(s, day: day, hour: hour, minute: minute, now: now, today: today, calendar: calendar)
        result.text = result.text.replacingOccurrences(of: placeholder, with: "一点")
        return result
    }

    private static func finish(_ rest: String, day: Date?, hour: Int?, minute: Int,
                               now: Date, today: Date, calendar: Calendar) -> Result {
        var s = rest
        // 只说了时段没说几点（"明天上午去洗车"），去掉时段词
        _ = match("^\\s*(?:\(period))", in: &s)
        let text = clean(s)
        let finalText = text.isEmpty ? clean(rest) : text

        guard let hour else {
            return Result(text: finalText, dueDate: day, hasTime: false)
        }
        var date = calendar.date(bySettingHour: min(hour, 23), minute: min(minute, 59), second: 0, of: day ?? today) ?? today
        // 只说了时间没说日期：今天已过就算明天
        if day == nil, date <= now, let next = calendar.date(byAdding: .day, value: 1, to: date) {
            date = next
        }
        return Result(text: finalText, dueDate: date, hasTime: true)
    }

    private static func adjust(hour: Int, period: String) -> Int {
        switch period {
        case "下午", "傍晚", "晚上", "夜里":
            return hour < 12 ? hour + 12 : hour
        case "中午":
            return hour < 6 ? hour + 12 : hour
        case "":
            // 口语里"两点开会"一般指下午
            return (1...5).contains(hour) ? hour + 12 : hour
        default:
            return period == "凌晨" && hour == 12 ? 0 : hour
        }
    }

    /// 去掉首尾的标点、空白和"提醒我"之类的引导词
    private static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for prefix in ["提醒我", "记得"] where t.hasPrefix(prefix) && t.count > prefix.count {
            t.removeFirst(prefix.count)
            t = t.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
        return t
    }

    /// 匹配第一个出现的位置，从 s 中删掉匹配到的文字，返回各捕获组（未匹配的组为空串）
    private static func match(_ pattern: String, in s: inout String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let whole = Range(m.range, in: s) else { return nil }
        let groups = (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
        }
        s.replaceSubrange(whole, with: "")
        return groups
    }

    private static func weekdayIndex(_ c: String) -> Int? {
        switch c {
        case "一", "1": 0
        case "二", "2": 1
        case "三", "3": 2
        case "四", "4": 3
        case "五", "5": 4
        case "六", "6": 5
        case "日", "天", "7": 6
        default: nil
        }
    }

    /// "14" "十四" "二十" "两" "二〇二六" → 整数
    static func number(_ s: String) -> Int? {
        if s.isEmpty { return nil }
        if let n = Int(s) { return n }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
                                        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if let ten = s.firstIndex(of: "十") {
            let left = s[..<ten], right = s[s.index(after: ten)...]
            let tens = left.isEmpty ? 1 : left.count == 1 ? digits[left.first!] : nil
            let ones = right.isEmpty ? 0 : right.count == 1 ? digits[right.first!] : nil
            guard let tens, let ones else { return nil }
            return tens * 10 + ones
        }
        var n = 0
        for c in s {
            guard let d = digits[c] else { return nil }
            n = n * 10 + d
        }
        return n
    }
}
