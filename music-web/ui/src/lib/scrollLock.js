// Blocca lo scorrimento della pagina sotto le schermate a tutto schermo
// (wizard, lettore). Più blocchi insieme: si sblocca quando l'ultimo si chiude.
let locks = 0;

export function lockScroll() {
  if (locks++ === 0) document.documentElement.classList.add("no-scroll");
  return () => {
    if (--locks === 0) document.documentElement.classList.remove("no-scroll");
  };
}
