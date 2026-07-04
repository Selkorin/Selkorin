package com.selkorin.ege;

/** Карточка: лицевая сторона (термин/вопрос), обратная (ответ) и мнемоника. */
public class Flashcard {
    public final String subject;
    public final String front;
    public final String back;
    public final String mnemonic;

    public Flashcard(String subject, String front, String back, String mnemonic) {
        this.subject = subject;
        this.front = front;
        this.back = back;
        this.mnemonic = mnemonic;
    }
}
