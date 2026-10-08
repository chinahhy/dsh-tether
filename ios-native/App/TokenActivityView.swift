import SwiftUI

private enum TokenProvider: String, CaseIterable, Identifiable {
    case all, deepseek, codex, kimi
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .deepseek: "DeepSeek"
        case .codex: "Codex"
        case .kimi: "Kimi"
        }
    }
}

private struct ActivityDay: Identifiable {
    let date: Date
    let tokens: Int?
    var id: Date { date }
}

/// Synthetic activity only. No inference is made from a provider balance or bill.
struct TokenActivityView: View {
    @State private var provider: TokenProvider = .all
    @State private var periodOffset = 0
    @State private var selectedDate: Date?

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }
    private var start: Date {
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday - 84 - periodOffset * 91, to: today) ?? today
    }
    private var days: [ActivityDay] {
        (0..<91).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: start) else { return nil }
            return ActivityDay(date: date, tokens: date > today ? nil : tokenCount(on: date))
        }
    }
    private var total: Int { days.reduce(0) { $0 + ($1.tokens ?? 0) } }
    private var activeDays: Int { days.filter { ($0.tokens ?? 0) > 0 }.count }
    private var selected: ActivityDay? {
        days.first(where: { $0.date == selectedDate && $0.tokens != nil }) ??
        days.last(where: { $0.tokens != nil })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Token 活动").font(.headline).foregroundStyle(PreviewStyle.ink)
                Spacer()
                Text("演示数据").font(.caption).foregroundStyle(PreviewStyle.muted)
            }
            HStack(spacing: 28) {
                metric("这段时间使用", value: total.formatted(), unit: "Token")
                metric("活跃天数", value: "\(activeDays)", unit: "天")
            }
            HStack {
                Button { periodOffset = min(3, periodOffset + 1); selectedDate = nil } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(periodOffset >= 3)
                Spacer()
                Text(periodLabel).font(.caption).foregroundStyle(PreviewStyle.muted)
                Spacer()
                Button { periodOffset = max(0, periodOffset - 1); selectedDate = nil } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(periodOffset == 0)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(TokenProvider.allCases) { item in
                        Button(item.title) { provider = item; selectedDate = nil }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(provider == item ? .white : PreviewStyle.muted)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(provider == item ? PreviewStyle.blue : PreviewStyle.canvas,
                                        in: Capsule())
                    }
                }
            }
            HStack(alignment: .top, spacing: 3) {
                VStack(spacing: 4) {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                        Text(day).font(.system(size: 8))
                            .foregroundStyle(PreviewStyle.muted)
                            .frame(width: 12, height: 13)
                    }
                }
                ForEach(0..<13, id: \.self) { week in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let index = week * 7 + weekday
                            if days.indices.contains(index) {
                                dayCell(days[index])
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 4) {
                Text("少")
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(for: level))
                        .frame(width: 12, height: 12)
                }
                Text("多")
            }
            .font(.caption2)
            .foregroundStyle(PreviewStyle.muted)
            if let selected {
                Label("\(selected.date.formatted(date: .abbreviated, time: .omitted)) · \((selected.tokens ?? 0).formatted()) Token",
                      systemImage: "chart.bar.xaxis")
                    .font(.caption).foregroundStyle(PreviewStyle.ink)
            }
            Text("每日 Token 数为模拟值，不代表真实账户统计或账单。")
                .font(.caption2).foregroundStyle(PreviewStyle.muted)
        }
        .padding(17)
        .background(.white, in: RoundedRectangle(cornerRadius: 15))
    }

    private var periodLabel: String {
        let end = days.last(where: { $0.tokens != nil })?.date ?? start
        return "\(start.formatted(.dateTime.month().day())) — \(end.formatted(.dateTime.month().day()))"
    }

    private func metric(_ title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(PreviewStyle.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.bold()).foregroundStyle(PreviewStyle.ink)
                Text(unit).font(.caption2).foregroundStyle(PreviewStyle.muted)
            }
        }
    }

    private func dayCell(_ day: ActivityDay) -> some View {
        Button {
            selectedDate = day.date
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(day.tokens.map { color(for: level($0)) } ?? PreviewStyle.canvas)
                .frame(width: 13, height: 13)
                .overlay {
                    if selected?.date == day.date {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(PreviewStyle.ink.opacity(0.8), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(day.tokens == nil)
        .accessibilityLabel("\(day.date.formatted(date: .abbreviated, time: .omitted))，\((day.tokens ?? 0).formatted()) Token")
    }

    private func level(_ tokens: Int) -> Int {
        if tokens == 0 { return 0 }
        if tokens < 15_000 { return 1 }
        if tokens < 35_000 { return 2 }
        if tokens < 65_000 { return 3 }
        return 4
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 0: PreviewStyle.canvas
        case 1: PreviewStyle.blue.opacity(0.22)
        case 2: PreviewStyle.blue.opacity(0.42)
        case 3: PreviewStyle.blue.opacity(0.68)
        default: PreviewStyle.blue
        }
    }

    private func tokenCount(on date: Date) -> Int {
        let day = Int(date.timeIntervalSince1970 / 86_400)
        func count(salt: Int, factor: Int) -> Int {
            let mixed = (day * 73 + salt * 101 + (day % 29) * salt) % 97
            return mixed % 8 < 2 ? 0 : (mixed / 8 + 2) * factor
        }
        switch provider {
        case .deepseek: count(salt: 13, factor: 1_950)
        case .codex: count(salt: 37, factor: 2_600)
        case .kimi: count(salt: 71, factor: 850)
        case .all:
            count(salt: 13, factor: 1_950) + count(salt: 37, factor: 2_600) +
            count(salt: 71, factor: 850)
        }
    }
}
