import SwiftUI
import LightPlanCore

struct PlansView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var systemLocale
    @AppStorage("language") private var language = "system"
    @State private var create = false
    @State private var deleting: ShootPlan?
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var filter: PlanLibraryFilter = .all
    @State private var entries: [PlanLibraryEntry] = []
    @State private var entriesRevision = UUID()
    @State private var visibleGroups: [PlanLibraryGroup] = []
    @State private var publishedQuery: QueryRequest?
    @State private var queryFailed = false
    @State private var referenceDate = Date()
    @State private var loading = false
    @State private var resolving = false
    @State private var failed = false
    @State private var generation = UUID()
    @State private var timeResolver = PlanLibraryTimeResolver()

    private struct Request: Equatable {
        let plans: [ShootPlan]
        let now: Date
    }
    private var request: Request { Request(plans: state.plans, now: referenceDate) }
    private struct QueryRequest: Equatable {
        let revision: UUID
        let query: String
        let filter: PlanLibraryFilter
        let localeID: String
    }
    private var queryRequest: QueryRequest {
        QueryRequest(revision: entriesRevision, query: query, filter: filter,
                     localeID: language == "system" ? systemLocale.identifier : L10n.locale.identifier)
    }
    private var queryPending: Bool { publishedQuery != queryRequest }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if state.plans.isEmpty { emptyLibrary }
                else {
                    libraryControls
                    if loading || queryPending {
                        ProgressView().frame(maxWidth: .infinity)
                            .accessibilityLabel(L10n.text("flow.searching"))
                            .accessibilityIdentifier("plan-library-query-busy")
                    }
                    if resolving {
                        HStack {
                            ProgressView()
                            KeyText("library.resolving").font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.accessibilityIdentifier("plan-library-resolving")
                    }
                    if failed || queryFailed {
                        LPCard {
                            VStack(alignment: .leading, spacing: 12) {
                                KeyText("error.calculation")
                                Button(L10n.text("library.retry")) { referenceDate = Date() }
                            }
                        }
                    }
                    if visibleGroups.isEmpty && !queryPending && !loading && !resolving && !failed && !queryFailed { emptyResults }
                    if !queryPending && !visibleGroups.isEmpty {
                        ForEach(visibleGroups) { group in
                            LazyVStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label(group.name ?? L10n.text("library.unfiled"), systemImage: "folder")
                                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Text(L10n.number(Double(group.entries.count))).font(.subheadline).foregroundStyle(.secondary)
                                }.accessibilityIdentifier("plan-collection-heading")
                                ForEach(group.entries) { entry in
                                    NavigationLink(value: entry.plan.id) { PlanLibraryCard(entry: entry) }
                                        .buttonStyle(LPPressStyle()).accessibilityIdentifier("plan-card")
                                        .contextMenu {
                                            Button {
                                                Task { await state.setPlanCompleted(entry.plan, completed: entry.plan.completedAt == nil) }
                                            } label: {
                                                Label(L10n.text(entry.plan.completedAt == nil ? "library.markCompleted" : "library.reopen"),
                                                      systemImage: entry.plan.completedAt == nil ? "checkmark.circle" : "arrow.uturn.backward")
                                            }
                                            Button(role: .destructive) { deleting = entry.plan } label: {
                                                Label(L10n.text("common.delete"), systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
            }.padding(18).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LPTheme.canvas).navigationTitle(L10n.text("tab.plans"))
        .toolbar {
            Button { create = true } label: { Image(systemName: "plus").accessibilityLabel(L10n.text("plan.create")) }
                .accessibilityIdentifier("plan-create")
        }
        .sheet(isPresented: $create) { NavigationStack { PlanEditorView() } }
        .confirmationDialog(L10n.text("plan.deleteConfirm"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(L10n.text("common.delete"), role: .destructive) {
                if let plan = deleting { Task { await state.deletePlan(plan) } }; deleting = nil
            }
        }
        .navigationDestination(item: $state.openPlanID) { id in
            if let plan = state.plans.first(where: { $0.id == id }) { PlanDetailView(plan: plan) }
            else { KeyText("plan.notFound") }
        }
        .navigationDestination(for: UUID.self) { id in
            if let plan = state.plans.first(where: { $0.id == id }) { PlanDetailView(plan: plan) }
            else { KeyText("plan.notFound") }
        }
        .task(id: request) { await reload(request) }
        .task(id: queryRequest) { await updateGroups(queryRequest) }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                // Do not cancel a large initial pass every minute. Once it finishes,
                // the next tick only reclassifies times using the retained cache.
                if scenePhase == .active && !loading && !resolving { referenceDate = Date() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // A foreground return may cross a destination midnight. Refresh the
            // snapshot then; completed cache work survives the cancelled batch.
            if phase == .active { referenceDate = Date() }
        }
        .onAppear { referenceDate = Date() }
        .accessibilityIdentifier("screen-plans")
    }

    private var libraryControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.text("library.search"), text: $query)
                    .focused($searchFocused)
                    .accessibilityIdentifier("plan-library-search").submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel(L10n.text("library.clearSearch"))
                        .accessibilityIdentifier("plan-library-clear-search")
                }
            }.padding(.horizontal, 14).frame(minHeight: 52)
                .background(LPTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                .contentShape(Rectangle())
                .onTapGesture { searchFocused = true }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { filterButtons }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { filterButtons }
                }
            }
        }
    }

    @ViewBuilder private var filterButtons: some View {
        ForEach(PlanLibraryFilter.allCases, id: \.self) { value in
            Button { filter = value } label: {
                Text(L10n.text("library.filter." + value.rawValue))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.vertical, typeSize.isAccessibilitySize ? 10 : 0)
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
                    .background(filter == value ? LPTheme.accent : LPTheme.surface, in: Capsule())
                    .foregroundStyle(filter == value ? Color.white : Color.primary)
            }.buttonStyle(.plain)
                .accessibilityAddTraits(filter == value ? .isSelected : [])
                .accessibilityIdentifier("plan-library-filter-" + value.rawValue)
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 18) {
            LPPhotoHero(asset: "hero-sunset", minimumHeight: 290) {
                VStack(alignment: .leading, spacing: 10) {
                    KeyText("v3.plan.emptyTitle").font(.largeTitle.bold())
                    KeyText("plan.emptyBody").font(.body)
                    KeyText("v3.art.label").font(.caption2).opacity(0.7)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 28))
            Button { create = true } label: {
                Label(L10n.text("plan.create"), systemImage: "calendar.badge.plus").font(.headline).frame(maxWidth: .infinity).padding(15)
            }.buttonStyle(.borderedProminent)
        }
    }

    private var emptyResults: some View {
        LPCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.text("library.noMatches"), systemImage: "line.3.horizontal.decrease.circle").font(.headline)
                KeyText("library.noMatchesBody").foregroundStyle(.secondary)
                Button(L10n.text("library.resetFilters")) { query = ""; filter = .all }
            }
        }.accessibilityIdentifier("plan-library-empty-results")
    }

    private func updateGroups(_ input: QueryRequest) async {
        let snapshot = entries
        queryFailed = false
        do {
            // Coalesce typing only. Initial rows and time-resolution batches don't
            // incur a debounce, and changing filters never redoes astronomy.
            if !input.query.isEmpty, publishedQuery?.query != input.query {
                try await Task.sleep(for: .milliseconds(120))
            }
            let result = try await PlanLibrary.groupsAsync(snapshot, query: input.query,
                filter: input.filter, locale: Locale(identifier: input.localeID))
            try Task.checkCancellation()
            guard queryRequest == input else { return }
            visibleGroups = result; publishedQuery = input
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, queryRequest == input else { return }
            visibleGroups = []; publishedQuery = input; queryFailed = true
        }
    }

    private func reload(_ input: Request) async {
        guard !Task.isCancelled else { return }
        let token = UUID()
        generation = token
        loading = true; resolving = false; failed = false
        defer {
            if generation == token { loading = false; resolving = false }
        }
        do {
            var working = try await timeResolver.prepare(plans: input.plans, now: input.now)
            try Task.checkCancellation()
            guard request == input, generation == token else { return }
            // Titles, projects, dates and known composition instants are available
            // immediately, including while thousands of distinct sites are resolved.
            entries = working; entriesRevision = UUID(); loading = false
            let pending = working.indices.filter { working[$0].needsTimeResolution }
            resolving = !pending.isEmpty
            for offset in stride(from: 0, to: pending.count, by: 64) {
                try Task.checkCancellation()
                let indices = Array(pending[offset..<min(offset + 64, pending.count)])
                let result = try await timeResolver.resolve(indices.map { working[$0] }, now: input.now)
                try Task.checkCancellation()
                guard request == input, generation == token else { return }
                for (index, value) in zip(indices, result) { working[index] = value }
                entries = working; entriesRevision = UUID()
                await Task.yield()
            }
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, request == input, generation == token else { return }
            failed = true
        }
    }
}

private struct PlanLibraryCard: View {
    let entry: PlanLibraryEntry
    private var plan: ShootPlan { entry.plan }
    var body: some View {
        LPPhotoHero(asset: plan.composition?.body == .moon ? "hero-coastal" : "hero-sunset", minimumHeight: 215) {
            VStack(alignment: .leading, spacing: 9) {
                if plan.completedAt != nil {
                    Label(L10n.text("library.filter.completed"), systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold))
                }
                Text(plan.title).font(.title2.bold()).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Label(plan.place.name, systemImage: "mappin.circle.fill").font(.subheadline).multilineTextAlignment(.leading)
                Text(L10n.text("target." + plan.target.rawValue)).font(.subheadline)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.fullDate(plan.date, zone: plan.place.timeZone))
                        if let anchor = entry.anchor { Text(L10n.time(anchor, zone: plan.place.timeZone)).monospacedDigit() }
                        if entry.needsTimeResolution { KeyText("library.timePending") }
                        if entry.hasNoEventToday { KeyText("plan.noEvent") }
                    }.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                }.font(.caption)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 26))
            .contentShape(RoundedRectangle(cornerRadius: 26))
    }
}
