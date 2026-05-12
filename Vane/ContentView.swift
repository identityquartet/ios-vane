import SwiftUI

struct ContentView: View {
    @State private var vm = SearchViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if vm.searchEngine.isSearx {
                    searxContent
                } else {
                    aiContent
                }
                Divider()
                SearchBar(vm: vm)
            }
            .navigationTitle("Vane")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if vm.searchEngine.isSearx {
                        if !vm.searxResults.isEmpty || vm.searxIsSearching {
                            Button { vm.clearSearxSearch() } label: {
                                Image(systemName: "xmark")
                            }
                        }
                    } else {
                        Button { vm.newChat() } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .disabled(vm.messages.isEmpty)
                    }
                }
                if vm.searchEngine.isSearx {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Time Range", selection: $vm.searxTimeRange) {
                                ForEach(SearchViewModel.TimeRange.allCases, id: \.self) { t in
                                    Text(t.label).tag(t)
                                }
                            }
                        } label: {
                            Image(systemName: vm.searxTimeRange == .anytime ? "clock" : "clock.badge.checkmark")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsSheet(vm: vm) }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
                Button("OK") { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
        }
        .task { await vm.loadConfig() }
    }

    @ViewBuilder
    private var aiContent: some View {
        if vm.messages.isEmpty {
            WelcomeView()
        } else {
            ConversationView(vm: vm)
        }
    }

    @ViewBuilder
    private var searxContent: some View {
        if vm.searxResults.isEmpty && !vm.searxIsSearching {
            SearxEmptyState()
        } else if vm.searxCategory == .images {
            ImageGrid(results: vm.searxResults)
        } else {
            SearxResultList(vm: vm)
        }
    }
}

// MARK: - AI: Welcome

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wind")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Vane")
                .font(.largeTitle.bold())
            Text("AI-powered search")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - AI: Conversation

struct ConversationView: View {
    @Bindable var vm: SearchViewModel
    @State private var followLatest = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(vm.messages) { msg in
                        MessageView(message: msg).id(msg.id)
                    }
                }
                .padding()
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentSize.height - geo.visibleRect.maxY < 80
            } action: { _, isAtBottom in
                followLatest = isAtBottom
            }
            .onChange(of: vm.messages.last?.response) {
                guard followLatest, let last = vm.messages.last else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: vm.messages.count) {
                followLatest = true
                if let last = vm.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - AI: Message

struct MessageView: View {
    let message: VaneMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 60)
                Text(message.query)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            if message.isResearching && message.response.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.75)
                    Text("Searching…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            if !message.response.isEmpty {
                Text(message.response)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if message.isSearching && !message.response.isEmpty {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }

            if !message.sources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SOURCES")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(message.sources.enumerated()), id: \.offset) { idx, source in
                                SourceCard(number: idx + 1, source: source)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
            }
        }
    }
}

// MARK: - AI: Source card

struct SourceCard: View {
    let number: Int
    let source: VaneSource

    var body: some View {
        Group {
            if let url = URL(string: source.url) {
                Link(destination: url) { cardContent }
                    .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("\(number)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(source.title)
                .font(.caption.bold())
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text(hostFrom(source.url))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 160, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func hostFrom(_ urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
    }
}

// MARK: - SearXNG: Empty state

struct SearxEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "globe")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(.quaternary)
            Text("Private · Open source · No tracking")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - SearXNG: Result list

struct SearxResultList: View {
    @Bindable var vm: SearchViewModel

    var body: some View {
        List {
            if vm.searxIsSearching {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Searching…").font(.subheadline).foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
                .padding(.vertical, 4)
            }

            if !vm.searxAnswers.isEmpty {
                Section {
                    ForEach(vm.searxAnswers, id: \.self) { ans in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(ans).font(.body)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section {
                ForEach(vm.searxResults) { r in ResultRow(result: r) }
            } header: {
                if vm.searxTotalResults > 0 {
                    Text("\(vm.searxTotalResults.formatted()) results")
                        .font(.caption).foregroundStyle(.tertiary).textCase(nil)
                }
            }

            if !vm.searxSuggestions.isEmpty {
                Section("Also try") {
                    ForEach(vm.searxSuggestions.prefix(5), id: \.self) { s in
                        Button {
                            vm.inputText = s
                            Task { await vm.search() }
                        } label: {
                            HStack {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.subheadline)
                                Text(s).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.left").foregroundStyle(.tertiary).font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - SearXNG: Result row

struct ResultRow: View {
    let result: SearchResult

    var body: some View {
        Button {
            if let url = URL(string: result.url) { UIApplication.shared.open(url) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(result.displayHost)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(result.title)
                    .font(.body.weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                if !result.content.isEmpty {
                    Text(result.content)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(3).multilineTextAlignment(.leading)
                }
                if let date = result.publishedDate, !date.isEmpty {
                    Text(shortDate(date))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if !result.engines.isEmpty {
                    EngineTagsRow(engines: result.engines)
                }
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { UIPasteboard.general.string = result.url } label: {
                Label("Copy URL", systemImage: "link")
            }
            Button {
                if let url = URL(string: result.url) { UIApplication.shared.open(url) }
            } label: {
                Label("Open in Safari", systemImage: "safari")
            }
            ShareLink(item: URL(string: result.url)!) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func shortDate(_ s: String) -> String {
        let fmts = ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"]
        let df = DateFormatter()
        for fmt in fmts {
            df.dateFormat = fmt
            if let d = df.date(from: s) {
                let rf = RelativeDateTimeFormatter()
                rf.unitsStyle = .abbreviated
                return rf.localizedString(for: d, relativeTo: Date())
            }
        }
        return String(s.prefix(10))
    }
}

// MARK: - SearXNG: Engine tags

struct EngineTagsRow: View {
    let engines: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(engines, id: \.self) { engine in
                    Text(engine.capitalized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
                }
            }
        }
        .padding(.top, 1)
    }
}

// MARK: - SearXNG: Image grid

struct ImageGrid: View {
    let results: [SearchResult]
    let cols = [GridItem(.adaptive(minimum: 150), spacing: 3)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 3) {
                ForEach(results) { r in
                    Button {
                        if let url = URL(string: r.url) { UIApplication.shared.open(url) }
                    } label: {
                        AsyncImage(url: URL(string: r.thumbnailSrc ?? r.imgSrc ?? "")) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                                    .frame(height: 140).clipped()
                            case .failure, .empty:
                                Color(.systemGray5).frame(height: 140)
                                    .overlay { Image(systemName: "photo").foregroundStyle(.tertiary) }
                            @unknown default: EmptyView()
                            }
                        }
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        ShareLink(item: URL(string: r.url)!) {
                            Label("Share Page", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .padding(3)
        }
    }
}

// MARK: - Search bar

struct SearchBar: View {
    @Bindable var vm: SearchViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Engine toggle
            HStack(spacing: 6) {
                ForEach(SearchViewModel.SearchEngine.allCases, id: \.self) { engine in
                    Button { vm.searchEngine = engine } label: {
                        Label(engine.label, systemImage: engine.icon)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                vm.searchEngine == engine
                                    ? Color.accentColor.opacity(0.15)
                                    : Color(.tertiarySystemBackground)
                            )
                            .foregroundStyle(
                                vm.searchEngine == engine ? Color.accentColor : .secondary
                            )
                            .clipShape(Capsule())
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // SearXNG: category scroll
            if vm.searchEngine.isSearx {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(SearchViewModel.SearchCategory.allCases, id: \.self) { cat in
                            Button {
                                vm.searxCategory = cat
                                if !vm.searxResults.isEmpty { Task { await vm.search() } }
                            } label: {
                                Label(cat.label, systemImage: cat.icon)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 11).padding(.vertical, 6)
                                    .background(vm.searxCategory == cat ? Color.accentColor : Color(.tertiarySystemBackground))
                                    .foregroundStyle(vm.searxCategory == cat ? .white : .secondary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: vm.searxCategory)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }

            VStack(spacing: 8) {
                // AI: optimization mode
                if !vm.searchEngine.isSearx {
                    HStack(spacing: 6) {
                        ForEach(SearchViewModel.OptimizationMode.allCases, id: \.self) { mode in
                            Button { vm.optimizationMode = mode } label: {
                                Label(mode.label, systemImage: mode.icon)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        vm.optimizationMode == mode
                                            ? Color.accentColor.opacity(0.15)
                                            : Color(.tertiarySystemBackground)
                                    )
                                    .foregroundStyle(
                                        vm.optimizationMode == mode ? Color.accentColor : .secondary
                                    )
                                    .clipShape(Capsule())
                            }
                        }
                        Spacer()
                    }
                }

                // Input row
                HStack(alignment: .bottom, spacing: 8) {
                    if vm.searchEngine.isSearx {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 15))
                            TextField("Search…", text: $vm.inputText)
                                .focused($focused)
                                .submitLabel(.search)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onSubmit { submit() }
                            if !vm.inputText.isEmpty {
                                Button { vm.inputText = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        TextField("Ask anything…", text: $vm.inputText, axis: .vertical)
                            .lineLimit(1...4)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .focused($focused)
                            .disabled(vm.isSearching)
                            .onSubmit { submit() }
                    }

                    if vm.isProcessing {
                        Button { vm.cancelSearch() } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(Color.accentColor)
                        }
                    } else {
                        Button { submit() } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(canSend ? Color.accentColor : .gray)
                        }
                        .disabled(!canSend)
                    }
                }

            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
    }

    private var canSend: Bool {
        guard !vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return vm.searchEngine.isSearx ? !vm.searxIsSearching : !vm.isSearching
    }

    private func submit() {
        focused = false
        vm.startSearch()
    }
}

// MARK: - Settings

struct SettingsSheet: View {
    @Bindable var vm: SearchViewModel
    @Environment(\.dismiss) var dismiss
    @State private var serverDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://host:3000", text: $serverDraft)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } header: { Text("Vane Server URL") } footer: {
                    Text("Address of your Vane instance (used for AI search).")
                }
                Section {
                    Button("Save & Reconnect") {
                        vm.serverURL = serverDraft
                        Task { await vm.loadConfig() }
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { serverDraft = vm.serverURL }
        }
    }
}
