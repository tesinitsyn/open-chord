import SwiftUI

struct AuthenticationView: View {
    private enum Step { case server, account(ServerCapabilities) }
    private enum Action: String, CaseIterable { case login = "Sign In"; case register = "Create Account" }

    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var catalog: CatalogStore
    @State private var step: Step = .server
    @State private var address = ""
    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var action: Action = .login
    @State private var mode: ServerMode = .personal
    @State private var checking = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    brand
                    Group {
                        switch step {
                        case .server: serverForm
                        case .account(let capabilities): accountForm(capabilities)
                        }
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .animation(.snappy, value: stepID)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 48)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarBackButtonHidden()
        }
        .onAppear { address = catalog.serverURL.absoluteString }
    }

    private var brand: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 68))
                .symbolRenderingMode(.hierarchical)
            Text("OpenChord").font(.largeTitle.bold())
            Text("Your music. Your server.").foregroundStyle(.secondary)
        }
    }

    private var serverForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect to Server").font(.title2.bold())
            Text("Enter the URL provided by the person running your OpenChord server.")
                .foregroundStyle(.secondary)
            AuthenticationField(
                title: "Server address",
                placeholder: "192.168.1.20:8080",
                systemImage: "server.rack",
                text: $address,
                keyboardType: .URL,
                contentType: .URL,
                capitalizes: false
            )
                .accessibilityIdentifier("authServerAddress")
            errorLabel
            Button { Task { await connect() } } label: {
                HStack { if checking { ProgressView() }; Text(checking ? "Connecting…" : "Continue").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(checking || address.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func accountForm(_ capabilities: ServerCapabilities) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Button("Change Server", systemImage: "chevron.left") { withAnimation { step = .server } }
                .font(.subheadline.weight(.semibold))
            Text(capabilities.initialized ? action.rawValue : "Set Up This Server")
                .font(.title2.bold())
            if capabilities.initialized && capabilities.registrationEnabled {
                Picker("Account action", selection: $action) {
                    ForEach(Action.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if !capabilities.initialized {
                Picker("Server use", selection: $mode) {
                    Text("Just Me").tag(ServerMode.personal)
                    Text("Family").tag(ServerMode.family)
                }
                .pickerStyle(.segmented)
                Text(mode == .family ? "Anyone with this server URL can create a member account." : "Only this owner account will be allowed.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !capabilities.initialized || action == .register {
                AuthenticationField(
                    title: "Display name",
                    placeholder: "How others will see you",
                    systemImage: "person.text.rectangle",
                    text: $displayName,
                    contentType: .name
                )
            }
            AuthenticationField(
                title: "Username",
                placeholder: "Your sign-in name",
                systemImage: "at",
                text: $username,
                contentType: .username,
                capitalizes: false
            )
            AuthenticationField(
                title: "Password",
                placeholder: capabilities.initialized && action == .login
                    ? "Enter your password"
                    : "At least 10 characters",
                systemImage: "lock",
                text: $password,
                contentType: capabilities.initialized && action == .login
                    ? .password
                    : .newPassword,
                capitalizes: false,
                isSecure: true
            )
            errorLabel
            Button { Task { await submit(capabilities) } } label: {
                HStack { if auth.isWorking { ProgressView() }; Text(buttonTitle(capabilities)).frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(auth.isWorking || username.isEmpty || password.isEmpty || ((!capabilities.initialized || action == .register) && displayName.isEmpty))
        }
    }

    @ViewBuilder private var errorLabel: some View {
        if let message = localError ?? auth.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(.red)
        }
    }

    private func connect() async {
        checking = true; localError = nil; auth.errorMessage = nil
        defer { checking = false }
        do {
            guard let url = CatalogStore.normalizedURL(from: address) else { throw ServerAddressError.invalid }
            let capabilities = try await auth.capabilities(at: url)
            try catalog.configureServerAddress(address)
            action = capabilities.registrationEnabled ? .register : .login
            withAnimation(.snappy) { step = .account(capabilities) }
        } catch { localError = error.localizedDescription }
    }

    private func submit(_ capabilities: ServerCapabilities) async {
        if !capabilities.initialized {
            await auth.setup(username: username, displayName: displayName, password: password, mode: mode, serverURL: catalog.serverURL)
        } else if action == .register {
            await auth.register(username: username, displayName: displayName, password: password, serverURL: catalog.serverURL)
        } else {
            await auth.login(username: username, password: password, serverURL: catalog.serverURL)
        }
    }

    private func buttonTitle(_ capabilities: ServerCapabilities) -> String {
        if auth.isWorking { return "Please Wait…" }
        return capabilities.initialized ? action.rawValue : "Create Owner Account"
    }

    private var stepID: Int { if case .server = step { 0 } else { 1 } }
}

/// A focused, material-backed field shared by every authentication step.
private struct AuthenticationField: View {
    let title: String
    let placeholder: String
    let systemImage: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var contentType: UITextContentType?
    var capitalizes = true
    var isSecure = false

    @FocusState private var isFocused: Bool
    @State private var revealsSecureText = false

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isFocused ? .primary : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isFocused ? .primary : .secondary)

                field
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            if isSecure && !text.isEmpty {
                Button {
                    revealsSecureText.toggle()
                } label: {
                    Image(systemName: revealsSecureText ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealsSecureText ? "Hide password" : "Show password")
            } else if isFocused && !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(title.lowercased())")
            }
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 62)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.primary.opacity(isFocused ? 0.09 : 0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(Color.primary.opacity(isFocused ? 0.28 : 0.09), lineWidth: 1)
        }
        .shadow(color: Color.primary.opacity(isFocused ? 0.07 : 0), radius: 12)
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .onTapGesture { isFocused = true }
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }

    @ViewBuilder
    private var field: some View {
        if isSecure && !revealsSecureText {
            SecureField(placeholder, text: $text)
                .focused($isFocused)
                .textContentType(contentType)
        } else {
            TextField(placeholder, text: $text)
                .focused($isFocused)
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(capitalizes ? .sentences : .never)
                .autocorrectionDisabled(!capitalizes)
        }
    }
}
