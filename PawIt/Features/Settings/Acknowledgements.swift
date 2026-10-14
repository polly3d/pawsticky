import SwiftUI

/// 第三方开源组件声明。
///
/// MIT 等许可要求随附版权声明与许可文本，所以每个 SwiftPM 依赖都必须在这里有一条——
/// `scripts/preflight.sh` 会对照 `Core/Package.resolved` 检查，漏一个就失败。
struct Acknowledgement: Identifiable {
    let name: String
    let license: String
    let projectURL: URL
    /// 版权声明 + 许可文本（原样照抄上游 LICENSE，不要改写）。
    let notice: String

    var id: String { name }
}

enum Acknowledgements {
    static let all: [Acknowledgement] = [grdb]

    /// 本地 SQLite 存储层。上游：https://github.com/groue/GRDB.swift （LICENSE 原文，7.11.1 核对）。
    static let grdb = Acknowledgement(
        name: "GRDB.swift",
        license: "MIT License",
        projectURL: URL(string: "https://github.com/groue/GRDB.swift")!,
        notice: """
        Copyright (C) 2015-2025 Gwendal Roué

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    )
}

/// 设置 → About → Acknowledgements。
struct AcknowledgementsView: View {
    var body: some View {
        List {
            ForEach(Acknowledgements.all) { item in
                Section {
                    Text(item.notice)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .textSelection(.enabled)
                    Link(destination: item.projectURL) {
                        HStack {
                            Text("Project Page")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                } header: {
                    Text("\(item.name) · \(item.license)")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .warmBackground()
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
