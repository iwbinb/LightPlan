import SwiftUI
import LightPlanCore

struct FieldBriefView: View {
    let brief: PlanFieldBrief
    @Environment(\.openURL) private var openURL

    var body: some View {
        LPCard {
            VStack(alignment: .leading, spacing: 14) {
                Label(L10n.text("brief.title"), systemImage: "backpack").font(.headline)
                LabeledContent(L10n.text("brief.observer"), value: L10n.coordinate(brief.plan.place.coordinate))
                Text(brief.plan.place.timeZoneID).font(.caption).foregroundStyle(.secondary)
                if let notes = brief.plan.notes, !notes.isEmpty {
                    Text(notes).textSelection(.enabled).accessibilityIdentifier("saved-plan-notes")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { actions }
                    VStack(alignment: .leading, spacing: 12) { actions }
                }
                KeyText("brief.shareNote").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        Button { openURL(brief.mapURL) } label: {
            Label(L10n.text("brief.openMaps"), systemImage: "map")
        }.buttonStyle(.bordered).accessibilityIdentifier("plan-open-maps")
        ShareLink(item: shareText) {
            Label(L10n.text("brief.share"), systemImage: "square.and.arrow.up")
        }.buttonStyle(.bordered).accessibilityIdentifier("plan-share-brief")
    }

    private func stamp(_ date: Date) -> String {
        let zone = brief.plan.place.timeZone
        return L10n.fullDate(date, zone: zone) + " · " + L10n.time(date, zone: zone)
            + " (" + L10n.utcOffset(at: date, zone: zone) + ")"
    }

    private var shareText: String {
        let plan = brief.plan
        var lines = [plan.title, plan.place.name,
                     L10n.text("brief.observer") + ": " + L10n.coordinate(plan.place.coordinate),
                     L10n.text("place.timezone") + ": " + plan.place.timeZoneID,
                     L10n.text("plan.arrival") + ": " + stamp(brief.arriveAt),
                     L10n.text("brief.shootAt") + ": " + stamp(brief.shootAt),
                     L10n.text("target." + plan.target.rawValue)]
        if let collection = plan.collectionName, !collection.isEmpty { lines.append(L10n.text("plan.collection") + ": " + collection) }
        if plan.completedAt != nil { lines.append(L10n.text("library.completed")) }
        if let composition = plan.composition {
            lines += [L10n.text("body." + composition.body.rawValue),
                      L10n.text("composition.subject") + ": " + L10n.coordinate(composition.subject),
                      L10n.text("composition.targetOffset") + ": " + L10n.number(composition.desiredOffsetDegrees, decimals: 1) + "°"]
            if let constraints = composition.constraints { lines.append(L10n.conditions(constraints)) }
            if let framing = composition.cameraFraming {
                lines += [L10n.text("frame.focalLength") + ": " + L10n.focalLength(framing.focalLength35mm) + " mm",
                          L10n.text("frame." + framing.orientation.rawValue),
                          L10n.text("frame.referenceAltitude") + ": " + L10n.number(framing.referenceAltitudeDegrees, decimals: 1) + "°",
                          L10n.text("frame.modelNote")]
            }
            if let alignment = try? CompositionPlanner.evaluate(body: composition.body, at: composition.instant,
                observer: plan.place.coordinate, subject: composition.subject, desiredOffsetDegrees: composition.desiredOffsetDegrees) {
                lines += [L10n.text("composition.error") + ": " + L10n.number(alignment.absoluteErrorDegrees, decimals: 1) + "°",
                          L10n.text("composition.altitude") + ": " + L10n.number(alignment.altitude, decimals: 1) + "°"]
            }
        }
        if let notes = plan.notes, !notes.isEmpty { lines += ["", L10n.text("plan.notes") + ":", notes] }
        lines += ["", brief.mapURL.absoluteString, L10n.text("composition.geometryNote")]
        return lines.joined(separator: "\n")
    }
}
