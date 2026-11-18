import RiftsightCore
import SwiftUI

/// Smooth sparkline (Catmull-Rom), as in the KPI tiles.
struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.text
    var lineWidth: CGFloat = 1.6
    var fill = false

    var body: some View {
        GeometryReader { proxy in
            let points = normalized(in: proxy.size)
            ZStack {
                if fill, points.count > 1 {
                    smoothPath(points, closeTo: proxy.size.height)
                        .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                }
                smoothPath(points, closeTo: nil)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func normalized(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return [] }
        let span = max(hi - lo, 0.0001)
        return values.enumerated().map { index, value in
            CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: size.height * (1 - CGFloat((value - lo) / span)) * 0.88 + size.height * 0.06)
        }
    }

    private func smoothPath(_ points: [CGPoint], closeTo bottom: CGFloat?) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for i in 1..<points.count {
                let p0 = points[max(i - 2, 0)], p1 = points[i - 1], p2 = points[i], p3 = points[min(i + 1, points.count - 1)]
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                path.addCurve(to: p2, control1: c1, control2: c2)
            }
            if let bottom, let last = points.last {
                path.addLine(to: CGPoint(x: last.x, y: bottom))
                path.addLine(to: CGPoint(x: first.x, y: bottom))
                path.closeSubpath()
            }
        }
    }
}

/// Circular performance score (0–100) with an optional caption ("2nd", "MVP").
struct ScoreRing: View {
    let score: Int
    var caption: String?
    var size: CGFloat = 38
    var lineWidth: CGFloat = 3
    var showsValue = true

    var body: some View {
        let color = Theme.scoreColor(score)
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, score))) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsValue {
            VStack(spacing: -1) {
                Text("\(score)").font(Typo.number(size * 0.34, .bold)).foregroundStyle(Theme.text)
                if let caption {
                    Text(caption).font(.system(size: size * 0.17, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                }
            }
            }
        }
        .frame(width: size, height: size)
    }
}

/// Hexagonal radar chart (EARLY / MID / LATE / DAMAGE DEALT / DAMAGE TAKEN / SYNERGY).
struct RadarChart: View {
    let values: [Double]
    var compare: [Double]? = nil
    var labels: [String] = RadarValues.axisLabels
    var color: Color = Theme.redSideBar
    var compareColor: Color = Theme.blueSideBar
    var showLabels = true

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2 * (showLabels ? 0.62 : 0.92)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                ForEach(1...3, id: \.self) { ring in
                    polygon(Array(repeating: Double(ring) / 3, count: 6), center: center, radius: radius)
                        .stroke(Theme.border, lineWidth: 0.8)
                }
                if let compare {
                    polygon(compare, center: center, radius: radius).fill(compareColor.opacity(0.18))
                    polygon(compare, center: center, radius: radius).stroke(compareColor.opacity(0.8), lineWidth: 1.2)
                }
                polygon(values, center: center, radius: radius).fill(color.opacity(0.28))
                polygon(values, center: center, radius: radius).stroke(color, lineWidth: 1.5)
                if showLabels {
                    ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                        let point = vertex(index, value: 1.32, center: center, radius: radius)
                        Text(label)
                            .font(.system(size: 7, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize()
                            .position(point)
                    }
                }
            }
        }
    }

    private func vertex(_ index: Int, value: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2 + Double(index) * Double.pi / 3
        return CGPoint(x: center.x + CGFloat(cos(angle) * value) * radius, y: center.y + CGFloat(sin(angle) * value) * radius)
    }

    private func polygon(_ values: [Double], center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            for index in 0..<6 {
                let v = index < values.count ? min(1, max(0.05, values[index])) : 0.05
                let p = vertex(index, value: v, center: center, radius: radius)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
    }
}

/// Blue vs red probability bar with big percentages.
struct WinProbabilityBar: View {
    let blue: Double
    var title = "SIEGWAHRSCHEINLICHKEIT"

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(blue.percentString(digits: 0)).font(Typo.number(20, .bold)).foregroundStyle(Theme.blueSideBar)
                Spacer()
                Text(title).font(Typo.micro).tracking(0.8).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text((1 - blue).percentString(digits: 0)).font(Typo.number(20, .bold)).foregroundStyle(Theme.redSideBar)
            }
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.blueSideBar).frame(width: proxy.size.width * blue)
                    Rectangle().fill(Theme.redSideBar)
                }
                .clipShape(.capsule)
            }
            .frame(height: 6)
        }
        .animation(.smooth, value: blue)
    }
}
