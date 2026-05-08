// Test nested conditionals with #ifaot and #ifjit

#define DEBUG

#ifaot
    U0 AotMain() {
        #ifdef DEBUG
            U0 AotDebug() {
            }
        #endif
    }
    
    #ifdef DEBUG
    U0 AotDebugOuter() {
    }
    #endif
#endif

#ifjit
    U0 JitMain() {
        #ifdef DEBUG
            U0 JitDebug() {
            }
        #endif
    }
#endif

U0 Main() {
    AotMain();
    AotDebugOuter();
    // AotDebug() is local to AotMain
}

Main;
