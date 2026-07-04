package com.selkorin.ege;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * ЕГЭ Тренажёр 2026 — одностраничное приложение с экранами:
 * главная, меню предмета, тест, карточки, результат.
 * Весь UI строится программно (без XML-разметки).
 */
public class MainActivity extends Activity {

    // Палитра
    private static final int C_BG      = 0xFFEEF1F8;
    private static final int C_CARD    = 0xFFFFFFFF;
    private static final int C_PRIMARY = 0xFF4F46E5; // индиго
    private static final int C_PRIM_D  = 0xFF3730A3;
    private static final int C_ACCENT  = 0xFF0EA5A4; // бирюза
    private static final int C_OK      = 0xFF16A34A;
    private static final int C_BAD     = 0xFFDC2626;
    private static final int C_HINT_BG = 0xFFFFF7E0;
    private static final int C_HINT_BR = 0xFFF2C94C;
    private static final int C_TEXT    = 0xFF1F2937;
    private static final int C_MUTED   = 0xFF6B7280;

    private float density;
    private ScrollView root;
    private LinearLayout content;

    // Состояние теста
    private List<QItem> quiz;
    private int qIndex;
    private int score;
    private String quizTitle;

    // Состояние карточек
    private List<Flashcard> cards;
    private int cIndex;
    private boolean cardFlipped;

    private String screen = "home";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        density = getResources().getDisplayMetrics().density;

        root = new ScrollView(this);
        root.setBackgroundColor(C_BG);
        root.setFillViewport(true);
        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        int p = dp(18);
        content.setPadding(p, dp(24), p, dp(28));
        root.addView(content, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        setContentView(root);

        showHome();
    }

    // ------------------------------------------------------------------ helpers

    private int dp(float v) { return (int) (v * density + 0.5f); }

    private void clear() { content.removeAllViews(); root.scrollTo(0, 0); }

    private TextView text(String s, float sizeSp, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextColor(color);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setLineSpacing(dp(3), 1f);
        return t;
    }

    private GradientDrawable roundBg(int fill, int stroke, int strokePx, int radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(fill);
        g.setCornerRadius(dp(radiusDp));
        if (strokePx > 0) g.setStroke(strokePx, stroke);
        return g;
    }

    private LinearLayout card() {
        LinearLayout c = new LinearLayout(this);
        c.setOrientation(LinearLayout.VERTICAL);
        c.setBackground(roundBg(C_CARD, 0, 0, 16));
        int pd = dp(16);
        c.setPadding(pd, pd, pd, pd);
        return c;
    }

    private LinearLayout.LayoutParams lp(int topDp) {
        LinearLayout.LayoutParams l = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        l.topMargin = dp(topDp);
        return l;
    }

    private Button filledButton(String label, int color, View.OnClickListener onClick) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextColor(Color.WHITE);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        b.setTypeface(Typeface.DEFAULT_BOLD);
        b.setBackground(roundBg(color, 0, 0, 14));
        b.setPadding(dp(16), dp(14), dp(16), dp(14));
        b.setOnClickListener(onClick);
        b.setStateListAnimator(null);
        return b;
    }

    private Button outlineButton(String label, View.OnClickListener onClick) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextColor(C_PRIMARY);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        b.setTypeface(Typeface.DEFAULT_BOLD);
        b.setBackground(roundBg(0x00FFFFFF, C_PRIMARY, dp(1.4f), 14));
        b.setPadding(dp(16), dp(12), dp(16), dp(12));
        b.setOnClickListener(onClick);
        b.setStateListAnimator(null);
        return b;
    }

    // ------------------------------------------------------------------ HOME

    private void showHome() {
        screen = "home";
        clear();

        TextView title = text("ЕГЭ Тренажёр", 30, C_PRIM_D, true);
        content.addView(title);
        TextView year = text("2026", 30, C_ACCENT, true);
        content.addView(year);
        content.addView(text("Тесты и карточки с мнемоническими подсказками. "
                + "Контент учитывает изменения ФИПИ на 2026 год.", 14, C_MUTED, false), lp(6));

        // Быстрый смешанный тест
        LinearLayout mix = card();
        mix.setLayoutParams(lp(18));
        mix.addView(text("🎲 Случайный тест", 19, C_TEXT, true));
        mix.addView(text("20 вопросов из всех предметов вперемешку.", 13, C_MUTED, false), lp(4));
        Button mixBtn = filledButton("Начать смешанный тест", C_PRIMARY, new View.OnClickListener() {
            public void onClick(View v) { startMixedQuiz(); }
        });
        mixBtn.setLayoutParams(lp(12));
        mix.addView(mixBtn);
        content.addView(mix);

        content.addView(text("Выбери предмет", 18, C_TEXT, true), lp(22));

        String[] subs = Bank.subjects();
        for (int i = 0; i < subs.length; i++) {
            final String s = subs[i];
            int qn = Bank.questionsFor(s).size();
            int cn = Bank.flashcardsFor(s).size();

            LinearLayout row = card();
            row.setLayoutParams(lp(12));
            row.setOrientation(LinearLayout.VERTICAL);
            row.addView(text(Bank.icon(s) + "  " + s, 18, C_TEXT, true));
            row.addView(text(qn + " вопросов · " + cn + " карточек", 13, C_MUTED, false), lp(3));

            LinearLayout btns = new LinearLayout(this);
            btns.setOrientation(LinearLayout.HORIZONTAL);
            btns.setLayoutParams(lp(12));
            Button test = filledButton("📝 Тест", C_PRIMARY, new View.OnClickListener() {
                public void onClick(View v) { startSubjectQuiz(s); }
            });
            LinearLayout.LayoutParams tl = new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
            tl.rightMargin = dp(8);
            test.setLayoutParams(tl);
            Button flash = filledButton("🃏 Карточки", C_ACCENT, new View.OnClickListener() {
                public void onClick(View v) { startFlashcards(s); }
            });
            flash.setLayoutParams(new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            btns.addView(test);
            btns.addView(flash);
            row.addView(btns);
            content.addView(row);
        }

        content.addView(text("💡 Подсказка: в каждом задании можно открыть мнемонику — "
                + "короткую фразу-запоминалку.", 12, C_MUTED, false), lp(20));
    }

    // ------------------------------------------------------------------ QUIZ

    /** Элемент теста: вопрос с перемешанными вариантами. */
    private static class QItem {
        Question q;
        String[] opts;
        int correct;
    }

    private QItem makeItem(Question q) {
        QItem it = new QItem();
        it.q = q;
        List<Integer> idx = new ArrayList<Integer>();
        for (int i = 0; i < q.options.length; i++) idx.add(Integer.valueOf(i));
        Collections.shuffle(idx);
        it.opts = new String[idx.size()];
        for (int i = 0; i < idx.size(); i++) {
            int orig = idx.get(i).intValue();
            it.opts[i] = q.options[orig];
            if (orig == q.correct) it.correct = i;
        }
        return it;
    }

    private void startSubjectQuiz(String subject) {
        List<Question> qs = new ArrayList<Question>(Bank.questionsFor(subject));
        Collections.shuffle(qs);
        buildQuiz(qs, Bank.icon(subject) + "  " + subject);
    }

    private void startMixedQuiz() {
        List<Question> all = Bank.allQuestions();
        Collections.shuffle(all);
        int n = Math.min(20, all.size());
        buildQuiz(all.subList(0, n), "🎲  Смешанный тест");
    }

    private void buildQuiz(List<Question> qs, String title) {
        quiz = new ArrayList<QItem>();
        for (int i = 0; i < qs.size(); i++) quiz.add(makeItem(qs.get(i)));
        qIndex = 0;
        score = 0;
        quizTitle = title;
        screen = "quiz";
        showQuestion();
    }

    private void showQuestion() {
        clear();
        final QItem it = quiz.get(qIndex);

        content.addView(text(quizTitle, 15, C_PRIMARY, true));

        // Прогресс
        TextView prog = text("Вопрос " + (qIndex + 1) + " из " + quiz.size()
                + "   ·   Верно: " + score, 13, C_MUTED, false);
        content.addView(prog, lp(4));

        LinearLayout qcard = card();
        qcard.setLayoutParams(lp(12));
        qcard.addView(text(it.q.text, 18, C_TEXT, true));

        // Варианты
        final Button[] optButtons = new Button[it.opts.length];
        final TextView feedback = text("", 14, C_TEXT, false);
        final LinearLayout explBox = new LinearLayout(this);
        explBox.setOrientation(LinearLayout.VERTICAL);

        for (int i = 0; i < it.opts.length; i++) {
            final int choice = i;
            Button ob = new Button(this);
            ob.setText(it.opts[i]);
            ob.setAllCaps(false);
            ob.setTextColor(C_TEXT);
            ob.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
            ob.setGravity(Gravity.CENTER_VERTICAL | Gravity.START);
            ob.setBackground(roundBg(0xFFF3F4F6, 0xFFD1D5DB, dp(1.2f), 12));
            ob.setPadding(dp(16), dp(14), dp(16), dp(14));
            ob.setStateListAnimator(null);
            ob.setLayoutParams(lp(10));
            ob.setOnClickListener(new View.OnClickListener() {
                public void onClick(View v) {
                    answer(it, choice, optButtons, explBox);
                }
            });
            optButtons[i] = ob;
            qcard.addView(ob);
        }
        content.addView(qcard);

        // Кнопка подсказки-мнемоники
        final LinearLayout hintBox = new LinearLayout(this);
        hintBox.setOrientation(LinearLayout.VERTICAL);
        hintBox.setLayoutParams(lp(12));
        final Button hintBtn = outlineButton("💡 Подсказка (мнемоника)", null);
        hintBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                hintBox.removeAllViews();
                LinearLayout h = new LinearLayout(MainActivity.this);
                h.setOrientation(LinearLayout.VERTICAL);
                h.setBackground(roundBg(C_HINT_BG, C_HINT_BR, dp(1.4f), 12));
                int pd = dp(14);
                h.setPadding(pd, pd, pd, pd);
                h.addView(text("💡 Мнемоника", 13, 0xFF92700A, true));
                h.addView(text(it.q.mnemonic, 15, 0xFF7A5B05, false), lp(4));
                hintBox.addView(h);
            }
        });
        hintBox.addView(hintBtn);
        content.addView(hintBox);

        explBox.setLayoutParams(lp(12));
        content.addView(explBox);
    }

    private void answer(QItem it, int choice, Button[] optButtons, LinearLayout explBox) {
        // Блокируем повторные ответы
        for (int i = 0; i < optButtons.length; i++) {
            optButtons[i].setEnabled(false);
            if (i == it.correct) {
                optButtons[i].setBackground(roundBg(0xFFDCFCE7, C_OK, dp(1.6f), 12));
                optButtons[i].setTextColor(0xFF14532D);
            } else if (i == choice) {
                optButtons[i].setBackground(roundBg(0xFFFEE2E2, C_BAD, dp(1.6f), 12));
                optButtons[i].setTextColor(0xFF7F1D1D);
            }
        }

        boolean ok = (choice == it.correct);
        if (ok) score++;

        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setBackground(roundBg(ok ? 0xFFF0FDF4 : 0xFFFEF2F2, ok ? C_OK : C_BAD, dp(1.2f), 12));
        int pd = dp(14);
        box.setPadding(pd, pd, pd, pd);
        box.addView(text(ok ? "✅ Верно!" : "❌ Неверно", 16, ok ? C_OK : C_BAD, true));
        box.addView(text(it.q.explanation, 14, C_TEXT, false), lp(6));
        box.addView(text("💡 " + it.q.mnemonic, 14, 0xFF7A5B05, false), lp(8));
        explBox.addView(box);

        boolean last = (qIndex == quiz.size() - 1);
        Button next = filledButton(last ? "Показать результат" : "Далее →", C_PRIMARY,
                new View.OnClickListener() {
                    public void onClick(View v) {
                        if (qIndex == quiz.size() - 1) {
                            showResult();
                        } else {
                            qIndex++;
                            showQuestion();
                        }
                    }
                });
        next.setLayoutParams(lp(12));
        explBox.addView(next);
        // Прокрутим к разбору
        root.post(new Runnable() {
            public void run() { root.fullScroll(View.FOCUS_DOWN); }
        });
    }

    private void showResult() {
        screen = "result";
        clear();
        int total = quiz.size();
        int pct = total == 0 ? 0 : (int) Math.round(100.0 * score / total);

        String emoji, msg;
        if (pct >= 90)      { emoji = "🏆"; msg = "Блестяще! Ты почти готов к экзамену."; }
        else if (pct >= 70) { emoji = "🎉"; msg = "Отличный результат! Ещё немного практики."; }
        else if (pct >= 50) { emoji = "👍"; msg = "Неплохо. Повтори карточки со слабыми темами."; }
        else                { emoji = "📚"; msg = "Есть над чем поработать — начни с карточек."; }

        LinearLayout c = card();
        c.setGravity(Gravity.CENTER_HORIZONTAL);
        c.addView(text(emoji, 44, C_TEXT, false));
        c.addView(text(score + " / " + total, 34, C_PRIM_D, true), lp(6));
        c.addView(text(pct + "% правильных", 16, C_MUTED, false), lp(2));
        TextView m = text(msg, 15, C_TEXT, false);
        m.setGravity(Gravity.CENTER);
        c.addView(m, lp(10));
        content.addView(c);

        Button again = filledButton("🔄 Пройти ещё раз", C_PRIMARY, new View.OnClickListener() {
            public void onClick(View v) {
                qIndex = 0; score = 0;
                for (int i = 0; i < quiz.size(); i++) {
                    quiz.set(i, makeItem(quiz.get(i).q));
                }
                screen = "quiz";
                showQuestion();
            }
        });
        again.setLayoutParams(lp(16));
        content.addView(again);

        Button home = outlineButton("🏠 На главную", new View.OnClickListener() {
            public void onClick(View v) { showHome(); }
        });
        home.setLayoutParams(lp(10));
        content.addView(home);
    }

    // ------------------------------------------------------------------ FLASHCARDS

    private void startFlashcards(String subject) {
        cards = new ArrayList<Flashcard>(Bank.flashcardsFor(subject));
        Collections.shuffle(cards);
        cIndex = 0;
        cardFlipped = false;
        screen = "cards";
        showCard();
    }

    private void showCard() {
        clear();
        final Flashcard fc = cards.get(cIndex);

        content.addView(text(Bank.icon(fc.subject) + "  " + fc.subject, 15, C_ACCENT, true));
        content.addView(text("Карточка " + (cIndex + 1) + " из " + cards.size()
                + "   ·   нажми, чтобы перевернуть", 13, C_MUTED, false), lp(4));

        LinearLayout cardView = new LinearLayout(this);
        cardView.setOrientation(LinearLayout.VERTICAL);
        cardView.setBackground(roundBg(cardFlipped ? 0xFFEFFcFB : C_CARD,
                cardFlipped ? C_ACCENT : 0xFFE5E7EB, dp(1.6f), 18));
        int pd = dp(22);
        cardView.setPadding(pd, dp(30), pd, dp(30));
        cardView.setMinimumHeight(dp(230));
        cardView.setGravity(Gravity.CENTER);
        cardView.setLayoutParams(lp(14));

        if (!cardFlipped) {
            TextView label = text("ВОПРОС", 12, C_MUTED, true);
            label.setGravity(Gravity.CENTER);
            cardView.addView(label);
            TextView front = text(fc.front, 21, C_TEXT, true);
            front.setGravity(Gravity.CENTER);
            cardView.addView(front, lp(12));
            TextView tap = text("👆 нажми, чтобы увидеть ответ", 13, C_MUTED, false);
            tap.setGravity(Gravity.CENTER);
            cardView.addView(tap, lp(18));
        } else {
            TextView label = text("ОТВЕТ", 12, C_ACCENT, true);
            label.setGravity(Gravity.CENTER);
            cardView.addView(label);
            TextView back = text(fc.back, 18, C_TEXT, false);
            back.setGravity(Gravity.CENTER);
            cardView.addView(back, lp(10));

            LinearLayout h = new LinearLayout(this);
            h.setOrientation(LinearLayout.VERTICAL);
            h.setBackground(roundBg(C_HINT_BG, C_HINT_BR, dp(1.4f), 12));
            int hp = dp(14);
            h.setPadding(hp, hp, hp, hp);
            h.addView(text("💡 Мнемоника", 13, 0xFF92700A, true));
            h.addView(text(fc.mnemonic, 16, 0xFF7A5B05, false), lp(4));
            cardView.addView(h, lp(18));
        }

        cardView.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { cardFlipped = !cardFlipped; showCard(); }
        });
        content.addView(cardView);

        // Навигация
        LinearLayout nav = new LinearLayout(this);
        nav.setOrientation(LinearLayout.HORIZONTAL);
        nav.setLayoutParams(lp(14));

        Button prev = filledButton("← Назад", cIndex > 0 ? C_ACCENT : 0xFFB6C0C9,
                new View.OnClickListener() {
                    public void onClick(View v) {
                        if (cIndex > 0) { cIndex--; cardFlipped = false; showCard(); }
                    }
                });
        LinearLayout.LayoutParams pl = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        pl.rightMargin = dp(8);
        prev.setLayoutParams(pl);
        nav.addView(prev);

        boolean lastCard = (cIndex == cards.size() - 1);
        Button next = filledButton(lastCard ? "🔄 Сначала" : "Далее →", C_ACCENT,
                new View.OnClickListener() {
                    public void onClick(View v) {
                        cIndex = (cIndex + 1) % cards.size();
                        cardFlipped = false;
                        showCard();
                    }
                });
        next.setLayoutParams(new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        nav.addView(next);
        content.addView(nav);

        Button flipBtn = outlineButton(cardFlipped ? "↩ Показать вопрос" : "🔄 Перевернуть",
                new View.OnClickListener() {
                    public void onClick(View v) { cardFlipped = !cardFlipped; showCard(); }
                });
        flipBtn.setLayoutParams(lp(10));
        content.addView(flipBtn);

        Button home = outlineButton("🏠 На главную", new View.OnClickListener() {
            public void onClick(View v) { showHome(); }
        });
        home.setLayoutParams(lp(10));
        content.addView(home);
    }

    // ------------------------------------------------------------------ back

    @Override
    public void onBackPressed() {
        if ("home".equals(screen)) {
            super.onBackPressed();
        } else {
            showHome();
        }
    }
}
