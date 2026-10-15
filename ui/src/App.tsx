import { TooltipProvider } from "@/components/ui/tooltip"
import { ClaudePage } from "@/pages/claude-page"

// Отдельное приложение: весь экран — чат (слева чаты и фон, в центре разговор, справа контекст)
export function App() {
  return (
    <TooltipProvider delayDuration={150}>
      <ClaudePage />
    </TooltipProvider>
  )
}

export default App
