import SwiftUI

struct AnimatedContentWrapper<Content: View>: View {
    let content: Content
    let delay: Double
    
    init(delay: Double = 0, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.delay = delay
    }
    
    @State private var isVisible = false
    
    var body: some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(delay)) {
                    isVisible = true
                }
            }
    }
}

