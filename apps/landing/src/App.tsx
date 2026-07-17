import { useState } from 'react'
import './App.css'

function App() {
  const [count, setCount] = useState(0)

  return (
    <main>
      <h1>macwlt</h1>
      <p>Landing page scaffold</p>
      <button type="button" onClick={() => setCount((value) => value + 1)}>
        count is {count}
      </button>
    </main>
  )
}

export default App
