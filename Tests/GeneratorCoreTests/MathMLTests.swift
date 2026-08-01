import CoreFP
import Testing

@testable import GeneratorCore

@Suite("MathML")
struct MathMLTests {
    @Test("mi/mo/mn render as escaped leaf elements")
    func leafElements() {
        #expect(mi("A").rendered == "<mi>A</mi>")
        #expect(mo("×").rendered == "<mo>×</mo>")
        #expect(mn("2").rendered == "<mn>2</mn>")
        #expect(mi("<script>").rendered == "<mi>&lt;script&gt;</mi>")
    }

    @Test("msup wraps base and exponent as two children")
    func superscript() {
        #expect(msup(mi("C"), mi("A")).rendered == "<msup><mi>C</mi><mi>A</mi></msup>")
    }

    @Test("mrow concatenates children without extra markup")
    func row() {
        let row = mrow(mconcat([mi("A"), mo("×"), mi("B")]))

        #expect(row.rendered == "<mrow><mi>A</mi><mo>×</mo><mi>B</mi></mrow>")
    }

    @Test("math wraps content with the MathML namespace")
    func mathWrapper() {
        #expect(math(mi("A")).rendered == "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mi>A</mi></math>")
    }

    @Test("displayEquation wraps math in a block container")
    func display() {
        #expect(displayEquation(mi("A")).rendered.contains("<div class=\"equation\"><math"))
    }
}
