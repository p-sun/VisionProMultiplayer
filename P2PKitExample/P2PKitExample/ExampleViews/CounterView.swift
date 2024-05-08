//
//  CounterView.swift
//  P2PKitExample
//
//  Created by Paige Sun on 4/28/24.
//

import Foundation
import SwiftUI

struct CounterView: View {
    @StateObject private var syncedCount = P2PNetworkedEntity<Int>(name: "CounterView", initial: 1)
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Sync Value")
                .p2pTitleStyle()
            HStack {
                Button("+ 1") {
                    syncedCount.value = syncedCount.value + 1
                }.p2pButtonStyle()
                Text("Counter: \(syncedCount.value)")
                Spacer()
            }
        }.background(Color.yellow.opacity(0.3))
    }
}

#Preview {
    CounterView()
}
