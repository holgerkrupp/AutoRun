//
//  LaunchAtLoginView.swift
//  SeconClock2
//
//  Created by Holger Krupp on 17.08.23.
//

import SwiftUI
import ServiceManagement

struct LaunchAtLoginView: View {
    
    @State var sm = SMAppService()
    
    @State var onStart:Bool = false
        
    init(){
        onStart = SMAppService().status == .enabled ? true : false
    }
    
    var body: some View {
        Toggle(isOn: $onStart, label: {
            Text("Launch at Login")
        })
        .onChange(of: onStart) { oldValue, newValue in
            switch newValue {
            case true:
                do {
                    try sm.register()
                }catch{
                    print("could not register Launch item")
                }
            case false:
                do {
                    try sm.unregister()
                    
                }catch{
                    print("could not unregister Launch item")
                    
                }
            }
        }
        
        
        
        
    }
}



#Preview {
    LaunchAtLoginView()
}
