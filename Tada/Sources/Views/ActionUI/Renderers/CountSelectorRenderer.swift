import SwiftUI

struct CountSelectorRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var selectedCount: Int = 1
    @State private var customCount: Int = 5
    @State private var showingCustomInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ForEach(1...4, id: \.self) { count in
                    Button {
                        selectedCount = count
                        showingCustomInput = false
                        response[field.id] = .number(Double(count))
                    } label: {
                        Text("\(count)")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 56, height: 56)
                            .background(selectedCount == count && !showingCustomInput ? Color.blue : Color(.controlBackgroundColor))
                            .foregroundColor(selectedCount == count && !showingCustomInput ? .white : .primary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    if count < 4 {
                        Spacer()
                    }
                }

                Spacer()

                Button {
                    showingCustomInput = true
                    selectedCount = customCount
                    response[field.id] = .number(Double(customCount))
                } label: {
                    if showingCustomInput {
                        HStack(spacing: 4) {
                            TextField("", value: $customCount, format: .number)
                                .textFieldStyle(.plain)
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 30)
                                .multilineTextAlignment(.center)
                                .onChange(of: customCount) { _, newValue in
                                    response[field.id] = .number(Double(newValue))
                                }
                            Stepper("", value: $customCount, in: 5...99)
                                .labelsHidden()
                                .onChange(of: customCount) { _, newValue in
                                    response[field.id] = .number(Double(newValue))
                                }
                        }
                        .frame(width: 80, height: 56)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    } else {
                        Text("5+")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 56, height: 56)
                            .background(Color(.controlBackgroundColor))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            response[field.id] = .number(Double(selectedCount))
        }
    }
}

