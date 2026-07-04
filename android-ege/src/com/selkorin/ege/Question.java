package com.selkorin.ege;

/** Один тестовый вопрос ЕГЭ: формулировка, 4 варианта, индекс верного,
 *  разбор и мнемоническая подсказка. */
public class Question {
    public final String subject;
    public final String text;
    public final String[] options;
    public final int correct;      // индекс правильного варианта (0..3)
    public final String explanation;
    public final String mnemonic;  // подсказка в стиле мнемоники

    public Question(String subject, String text, String[] options, int correct,
                    String explanation, String mnemonic) {
        this.subject = subject;
        this.text = text;
        this.options = options;
        this.correct = correct;
        this.explanation = explanation;
        this.mnemonic = mnemonic;
    }
}
