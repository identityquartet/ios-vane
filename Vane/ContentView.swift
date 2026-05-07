import SwiftUI

struct ContentView: View {
    @State private var vm = SearchViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if vm.messages.isEmpty {
                    WelcomeView()
                } else {
                    ConversationView(vm: vm)
                }
                Divider()
                SearchBar(vm: vm)
            }
            .navigationTitle("Vane")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { vm.newChat() } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(vm.messages.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet(vm: vm) }
        .task { await vm.loadConfig() }
    }
}

// MARK: - Welcome
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

// MARK: - Conversation
struct ConversationView: View {
    @Bindable var vm: SearchViewModel

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
            .onChange(of: vm.messages.last?.response) {
                if let last = vm.messages.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: vm.messages.count) {
                if let last = vm.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Message
struct MessageView: View {
    let message: VaneMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User query
            HStack {
                Spacer(minLength: 60)
                Text(message.query)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            // Response area
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

            // Sources
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

// MARK: - Source card
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

// MARK: - Search bar
struct SearchBar: View {
    @Bindable var vm: SearchViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
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
            .padding(.horizontal)

            if vm.searchEngine == .ai {
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
                .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(vm.searchEngine == .searxng ? "Search the web…" : "Ask anything…",
                          text: $vm.inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .focused($focused)
                    .disabled(vm.isSearching)
                    .onSubmit { submit() }

                Button { submit() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(canSend ? Color.accentColor : .gray)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
    }

    private var canSend: Bool {
        !vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty && !vm.isSearching
    }

    private func submit() {
        focused = false
        Task { await vm.search() }
    }
}

// MARK: - Settings
struct SettingsSheet: View {
    @Bindable var vm: SearchViewModel
    @Environment(\.dismiss) var dismiss
    @State private var serverDraft = ""
    @State private var searxngDraft = ""

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
                    TextField("https://search.example.com", text: $searxngDraft)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } header: { Text("SearXNG URL") } footer: {
                    Text("Address of a SearXNG instance with the JSON API enabled.")
                }
                Section {
                    Button("Save & Reconnect") {
                        vm.serverURL = serverDraft
                        vm.searxngURL = searxngDraft
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
            .onAppear {
                serverDraft = vm.serverURL
                searxngDraft = vm.searxngURL
            }
        }
    }
}
