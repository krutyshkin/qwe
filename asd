import telebot
from telebot import types
from tinydb import TinyDB, Query
import time
from datetime import datetime, timedelta
from config import TOKEN, CHANNEL_ID, CHANNEL_LINK, ADMIN_CHANNEL_ID, ADMIN_ID, COEF_ODD, COEF_EVEN, COEF_LESS, COEF_MORE, COEF_GUESS, COEF_RAIN, COEF_SNOW, SNOW_CHANCE_IF_CHOSEN, RAIN_CHANCE_IF_CHOSEN
import random
from queue import Queue
import string

def create_bot():
    global BOT_USERNAME 
    bot = telebot.TeleBot(TOKEN)
    db = TinyDB('db.json')
    User = Query()
    bot_info = bot.get_me()
    BOT_USERNAME = bot_info.username
    bet_queue = Queue()
    bets_db = TinyDB('bets.json')
    payments_db = TinyDB('payments.json')

    def process_queue():
        while not bet_queue.empty():
            call = bet_queue.get()
            confirm_game(call)
            time.sleep(5)

    @bot.message_handler(commands=['start'])
    def start_handler(message):
        user_id = message.from_user.id
        username = message.from_user.username or "NoUsername"
        first_name = message.from_user.first_name
        last_name = message.from_user.last_name or ""
        param = message.text.split()[1] if len(message.text.split()) > 1 else None

        if not db.get(User.user_id == user_id):
            ref_code = ''.join(random.choice(string.ascii_uppercase + string.digits) for _ in range(12))
            db.insert({
                'user_id': user_id,
                'balance': 0,
                'bets_count': 0,
                'total_earned': 0,
                'reg_date': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                'first_name': first_name,
                'last_name': last_name,
                'ref_code': ref_code,
                'referrals': 0,
                'referred_by': None
            })

        if param and param != "bet":
            user_data = db.get(User.user_id == user_id)
            referrer = db.get(User.ref_code == param)
            if referrer and user_id not in db.search(User.referred_by == referrer['user_id']) and user_data['reg_date'] == datetime.now().strftime("%Y-%m-%d %H:%M:%S"):
                db.update({'referrals': referrer['referrals'] + 1}, User.user_id == referrer['user_id'])
                db.update({'referred_by': referrer['user_id']}, User.user_id == user_id)
                bot.send_message(referrer['user_id'], f"<b>По вашей реферальной ссылке перешел пользователь {first_name} {last_name}</b>", parse_mode='HTML', disable_web_page_preview=True)

        if param == "bet":
            user_data = db.get(User.user_id == user_id)
            bot.send_message(message.chat.id,
                            f"<b>Пришлите сумму звёзд для оплаты ставки.</b>\n\n"
                            f"Баланс: <code>{user_data['balance']} звёзд</code>",
                            parse_mode='HTML',
                            disable_web_page_preview=True)
            bot.register_next_step_handler(message, process_bet_amount)
        else:
            markup = types.ReplyKeyboardMarkup(resize_keyboard=True)
            btn_play = types.KeyboardButton("🎲 Играть")
            btn_profile = types.KeyboardButton("⚡️ Профиль")
            btn_ref = types.KeyboardButton("🔗 Реф. система")
            btn_add = types.KeyboardButton("💳 Пополнить баланс")
            btn_withdraw = types.KeyboardButton("💸 Вывести")
            btn_top = types.KeyboardButton("🏆 Топ")
            markup.add(btn_play)
            markup.add(btn_profile, btn_ref)
            markup.add(btn_add, btn_withdraw)
            markup.add(btn_top)
            
            bot.send_message(message.chat.id,
                            f"<b>👋 Добро пожаловать, @{username}</b>\n\n"
                            f"Канал со ставками - <a href='{CHANNEL_LINK}'>тык</a>",
                            parse_mode='HTML',
                            reply_markup=markup,
                            disable_web_page_preview=True)

    @bot.message_handler(commands=['give'])
    def give_stars(message):
        if message.from_user.id != ADMIN_ID:
            bot.send_message(message.chat.id, "<b>Эта команда только для админа!</b>", parse_mode='HTML', disable_web_page_preview=True)
            return
        try:
            amount = int(message.text.split()[1])
            if amount <= 0:
                bot.send_message(message.chat.id, "<b>Число должно быть положительным!</b>", parse_mode='HTML', disable_web_page_preview=True)
                return
            user_data = db.get(User.user_id == message.from_user.id)
            new_balance = user_data['balance'] + amount
            db.update({'balance': new_balance}, User.user_id == message.from_user.id)
            bot.send_message(message.chat.id, f"<b>Вы выдали себе {amount} звёзд. Новый баланс: {new_balance}</b>", parse_mode='HTML', disable_web_page_preview=True)
        except (IndexError, ValueError):
            bot.send_message(message.chat.id, "<b>Используйте: /give {число}</b>", parse_mode='HTML', disable_web_page_preview=True)

    @bot.message_handler(commands=['admin'])
    def admin_menu(message):
        if message.from_user.id != ADMIN_ID:
            bot.send_message(message.chat.id, "<b>Эта команда только для админа!</b>", parse_mode='HTML', disable_web_page_preview=True)
            return
        markup = types.InlineKeyboardMarkup()
        btn_give = types.InlineKeyboardButton("Выдать звёзды", callback_data="admin_give")
        btn_take = types.InlineKeyboardButton("Отобрать все звёзды", callback_data="admin_take")
        btn_stats = types.InlineKeyboardButton("Статистика", callback_data="admin_stats")
        markup.add(btn_give)
        markup.add(btn_take)
        markup.add(btn_stats)
        bot.send_message(message.chat.id, "<b>Админ меню</b>", parse_mode='HTML', reply_markup=markup, disable_web_page_preview=True)

    @bot.callback_query_handler(func=lambda call: call.data.startswith("admin_"))
    def admin_action(call):
        action = call.data.split("_")[1]
        if action == "give":
            bot.edit_message_text("<b>Введите ID пользователя</b>", call.message.chat.id, call.message.message_id, parse_mode='HTML', disable_web_page_preview=True)
            bot.register_next_step_handler_by_chat_id(call.message.chat.id, process_admin_give_id)
        elif action == "take":
            bot.edit_message_text("<b>Введите ID пользователя</b>", call.message.chat.id, call.message.message_id, parse_mode='HTML', disable_web_page_preview=True)
            bot.register_next_step_handler_by_chat_id(call.message.chat.id, process_admin_take_id)
        elif action == "stats":
            day_ago = datetime.now() - timedelta(days=1)
            week_ago = datetime.now() - timedelta(days=7)
            month_ago = datetime.now() - timedelta(days=30)
            
            bets_day = len(bets_db.search(Query().timestamp > day_ago.strftime("%Y-%m-%d %H:%M:%S")))
            bets_week = len(bets_db.search(Query().timestamp > week_ago.strftime("%Y-%m-%d %H:%M:%S")))
            bets_month = len(bets_db.search(Query().timestamp > month_ago.strftime("%Y-%m-%d %H:%M:%S")))
            bets_all = len(bets_db.all())
            
            payments_day = sum([p['amount'] for p in payments_db.search(Query().timestamp > day_ago.strftime("%Y-%m-%d %H:%M:%S"))])
            payments_week = sum([p['amount'] for p in payments_db.search(Query().timestamp > week_ago.strftime("%Y-%m-%d %H:%M:%S"))])
            payments_month = sum([p['amount'] for p in payments_db.search(Query().timestamp > month_ago.strftime("%Y-%m-%d %H:%M:%S"))])
            payments_all = sum([p['amount'] for p in payments_db.all()])
            
            markup = types.InlineKeyboardMarkup()
            btn_back = types.InlineKeyboardButton("Назад", callback_data="admin_back")
            markup.add(btn_back)
            
            bot.edit_message_text(
                f"<b>Статистика</b>\n\n"
                f"<b>Ставки:</b>\n"
                f"За сутки: <code>{bets_day}</code>\n"
                f"За неделю: <code>{bets_week}</code>\n"
                f"За месяц: <code>{bets_month}</code>\n"
                f"За все время: <code>{bets_all}</code>\n\n"
                f"<b>Пополнение:</b>\n"
                f"За сутки: <code>{payments_day}</code>\n"
                f"За неделю: <code>{payments_week}</code>\n"
                f"За месяц: <code>{payments_month}</code>\n"
                f"За все время: <code>{payments_all}</code>",
                call.message.chat.id, call.message.message_id, parse_mode='HTML', reply_markup=markup, disable_web_page_preview=True
            )

    def process_admin_give_id(message):
        try:
            user_id = int(message.text)
            bot.send_message(message.chat.id, "<b>Сколько выдать звёзд?</b>", parse_mode='HTML', disable_web_page_preview=True)
            bot.register_next_step_handler(message, lambda m: process_admin_give_amount(m, user_id))
        except ValueError:
            bot.send_message(message.chat.id, "<b>Введите корректный ID!</b>", parse_mode='HTML', disable_web_page_preview=True)

    def process_admin_give_amount(message, user_id):
        try:
            amount = int(message.text)
            if amount <= 0:
                bot.send_message(message.chat.id, "<b>Число должно быть положительным!</b>", parse_mode='HTML', disable_web_page_preview=True)
                return
            user_data = db.get(User.user_id == user_id)
            if user_data:
                new_balance = user_data['balance'] + amount
                db.update({'balance': new_balance}, User.user_id == user_id)
                bot.send_message(message.chat.id, f"<b>Пользователю {user_id} выдано {amount} звёзд</b>", parse_mode='HTML', disable_web_page_preview=True)
                bot.send_message(user_id, f"<b>Вам выдано {amount} звёзд администратором!</b>", parse_mode='HTML', disable_web_page_preview=True)
            else:
                bot.send_message(message.chat.id, "<b>Пользователь не найден!</b>", parse_mode='HTML', disable_web_page_preview=True)
        except ValueError:
            bot.send_message(message.chat.id, "<b>Введите корректное число!</b>", parse_mode='HTML', disable_web_page_preview=True)

    def process_admin_take_id(message):
        try:
            user_id = int(message.text)
            user_data = db.get(User.user_id == user_id)
            if user_data:
                db.update({'balance': 0}, User.user_id == user_id)
                bot.send_message(message.chat.id, "<b>Звёзды отобраны</b>", parse_mode='HTML', disable_web_page_preview=True)
                bot.send_message(user_id, "<b>Все ваши звёзды были отобраны администратором!</b>", parse_mode='HTML', disable_web_page_preview=True)
            else:
                bot.send_message(message.chat.id, "<b>Пользователь не найден!</b>", parse_mode='HTML', disable_web_page_preview=True)
        except ValueError:
            bot.send_message(message.chat.id, "<b>Введите корректный ID!</b>", parse_mode='HTML', disable_web_page_preview=True)

    @bot.callback_query_handler(func=lambda call: call.data == "admin_back")
    def admin_back(call):
        markup = types.InlineKeyboardMarkup()
        btn_give = types.InlineKeyboardButton("Выдать звёзды", callback_data="admin_give")
        btn_take = types.InlineKeyboardButton("Отобрать все звёзды", callback_data="admin_take")
        btn_stats = types.InlineKeyboardButton("Статистика", callback_data="admin_stats")
        markup.add(btn_give)
        markup.add(btn_take)
        markup.add(btn_stats)
        bot.edit_message_text("<b>Админ меню</b>", call.message.chat.id, call.message.message_id, parse_mode='HTML', reply_markup=markup, disable_web_page_preview=True)

    @bot.message_handler(func=lambda message: message.text == "💸 Вывести")
    def withdraw_stars_handler(message):
        user_id = message.from_user.id
        user_data = db.get(User.user_id == user_id)
        balance = user_data['balance']
        
        markup = types.InlineKeyboardMarkup(row_width=2)
        buttons = [
            types.InlineKeyboardButton("15 звёзд", callback_data="withdraw_15"),
            types.InlineKeyboardButton("25 звёзд", callback_data="withdraw_25"),
            types.InlineKeyboardButton("50 звёзд", callback_data="withdraw_50"),
            types.InlineKeyboardButton("100 звёзд", callback_data="withdraw_100"),
            types.InlineKeyboardButton("150 звёзд", callback_data="withdraw_150"),
            types.InlineKeyboardButton("350 звёзд", callback_data="withdraw_350"),
            types.InlineKeyboardButton("500000000 звёзд", callback_data="withdraw_500000000")
        ]
        markup.add(*buttons)
        
        bot.send_message(message.chat.id,
                        f"<b>Баланс:</b> <code>{balance} звёзд</code>\n\n"
                        f"<b>Выбери сумму звёзд которые вы хотите вывести.</b>",
                        parse_mode='HTML',
                        reply_markup=markup,
                        disable_web_page_preview=True)

    @bot.callback_query_handler(func=lambda call: call.data.startswith("withdraw_"))
    def withdraw_amount_choice(call):
        user_id = call.from_user.id
        user_data = db.get(User.user_id == user_id)
        count = int(call.data.split("_")[1])
        
        if user_data['balance'] < count:
            bot.answer_callback_query(call.id, "Недостаточно звёзд на балансе!")
            return
        
        markup = types.InlineKeyboardMarkup()
        btn_yes = types.InlineKeyboardButton("Да", callback_data=f"confirm_withdraw_{count}")
        btn_no = types.InlineKeyboardButton("Отмена", callback_data="cancel_withdraw")
        markup.add(btn_yes, btn_no)
        
        bot.edit_message_text(
            f"<b>Вы точно хотите вывести {count} звёзд?</b>",
            call.message.chat.id,
            call.message.message_id,
            parse_mode='HTML',
            reply_markup=markup,
            disable_web_page_preview=True
        )

    @bot.callback_query_handler(func=lambda call: call.data.startswith("confirm_withdraw_"))
    def confirm_withdraw(call):
        user_id = call.from_user.id
        count = int(call.data.split("_")[2])
        user_data = db.get(User.user_id == user_id)
        username = call.from_user.username or "NoUsername"
        
        new_balance = user_data['balance'] - count
        db.update({'balance': new_balance}, User.user_id == user_id)
        
        bot.edit_message_text(
            "<b>Вы подали заявку на вывод звёзд.</b>\n\n"
            "<b>В течение 72 часов заявка будет рассмотрена администратором и вам будет отправлен подарок, из которого вы получите звёзды.</b>",
            call.message.chat.id,
            call.message.message_id,
            parse_mode='HTML',
            disable_web_page_preview=True
        )
        
        markup = types.InlineKeyboardMarkup()
        btn_issued = types.InlineKeyboardButton("Выдано", callback_data=f"issued_{user_id}_{count}")
        markup.add(btn_issued)
        
        bot.send_message(
            ADMIN_CHANNEL_ID,
            f"<b>Новая заявка</b>\n\n"
            f"<blockquote><b>ID: {user_id}</b></blockquote>\n"
            f"<blockquote><b>Юзернейм: @{username}</b></blockquote>\n"
            f"<code>{count} звёзд</code>",
            parse_mode='HTML',
            reply_markup=markup,
            disable_web_page_preview=True
        )

    @bot.callback_query_handler(func=lambda call: call.data == "cancel_withdraw")
    def cancel_withdraw(call):
        bot.edit_message_text(
            "<b>Вывод звёзд отменён</b>",
            call.message.chat.id,
            call.message.message_id,
            parse_mode='HTML',
            disable_web_page_preview=True
        )

    @bot.callback_query_handler(func=lambda call: call.data.startswith("issued_"))
    def issue_withdraw(call):
        user_id = int(call.data.split("_")[1])
        count = int(call.data.split("_")[2])
        username = call.from_user.username or "NoUsername"
        
        bot.edit_message_text(
            f"<b>Новая заявка</b>\n\n"
            f"<blockquote><b>ID: {user_id}</b></blockquote>\n"
            f"<blockquote><b>Юзернейм: @{username}</b></blockquote>\n"
            f"<code>{count} звёзд</code>\n\n"
            f"<pre><b>Выдано</b></pre>",
            call.message.chat.id,
            call.message.message_id,
            parse_mode='HTML',
            disable_web_page_preview=True
        )
        
        bot.send_message(
            user_id,
            f"<b>✅ Ваша заявка была выполнена, ищите сообщение с подарком за {count} звёзд от нашего администратора.</b>",
            parse_mode='HTML',
            disable_web_page_preview=True
        )

    def process_bet_amount(message):
        try:
            user_id = message.from_user.id
            amount = int(message.text)
            user_data = db.get(User.user_id == user_id)
            if amount <= 0:
                bot.send_message(message.chat.id, "<b>Сумма звёзд должна быть больше нуля</b>", parse_mode='HTML', disable_web_page_preview=True)
                return
            if amount > user_data['balance']:
                bot.send_message(message.chat.id, "<b>Недостаточно звёзд на балансе!</b>", parse_mode='HTML', disable_web_page_preview=True)
                return
            
            markup = types.InlineKeyboardMarkup(row_width=2)
            btn_cube = types.InlineKeyboardButton("🎲 Куб", callback_data=f"cube_{amount}")333
            btn_cube_number = types.InlineKeyboardButton("🎲 Куб число", callback_data=f"cube_number_{amount}")
            btn_winter = types.InlineKeyboardButton("❄️ Зимние", callback_data=f"winter_{amount}")
            markup.add(btn_cube, btn_cube_number)
            markup.add(btn_winter)
            
            bot.send_message(message.chat.id,
                            f"<blockquote><b>🎮 Выберите игру, на которую хотите сделать ставку</b></blockquote>\n\n"
                            f"После оплаты, Ваша ставка сыграет в нашем <a href='{CHANNEL_LINK}'>канале</a>",
                            parse_mode='HTML',
                            reply_markup=markup,
                            disable_web_page_preview=True)
        except ValueError:
            bot.send_message(message.chat.id, "<b>Пожалуйста, введите число!</b>", parse_mode='HTML', disable_web_page_preview=True)
        except Exception as e:
            bot.send_message(message.chat.id, f"<b>Ошибка: {str(e)}</b>", parse_mode='HTML', disable_web_page_preview=True)

    @bot.callback_query_handler(func=lambda call: call.data.startswith("cube_") and not call.data.startswith("cube_number_"))
    def cube_choice(call):
        amount = int(call.data.split("_")[1])
        markup = types.InlineKeyboardMarkup(row_width=2)
        btn_odd = types.InlineKeyboardButton(f"Нечёт | {COEF_ODD}х", callback_data=f"game_odd_{amount}")
        btn_even = types.InlineKeyboardButton(f"Чёт | {COEF_EVEN}х", callback_data=f"game_even_{amount}")
        btn_less = types.InlineKeyboardButton(f"Меньше | {COEF_LESS}х", callback_data=f"game_less_{amount}")
        btn_more = types.InlineKeyboardButton(f"Больше | {COEF_MORE}х", callback_data=f"game_more_{amount}")
        markup.add(btn_odd, btn_even)
        markup.add(btn_less, btn_more)
        
        bot.edit_message_text(
            f"<blockquote><b>🎮 Выберите игру, на которую хотите сделать ставку</b></blockquote>\n\n"
            f"После оплаты, Ваша ставка сыграет в нашем <a href='{CHANNEL_LINK}'>канале</a>",
            call.message.chat.id,
            call.message.message_id,
            parse_mode='HTML',
            reply_markup=markup,
            disable_web_page_preview=True
        )

    @bot.callback_query_handler(func=lambda call: call.data.startswith("cube_number_"))
    def cube_number_choice(call):
        amount = int(call.data.split("_")[2])
        markup = types.InlineKeyboardMarkup(row_width=2)
        btn_1 = types.InlineKeyboardButton(f"1 | {COEF_GUESS}х", callback_data=f"game_guess_{amount}_1")
        btn_2 = types.InlineKeyboardButton(f"2 | {COEF_GUESS}х", callback_data=f"game_guess_{amount}_2")
        btn_3 = types.InlineKeyboardButton(f"3 | {COEF_GUESS}х", callback_data=f"game_guess_{amount}_3")
        btn_4 = types.InlineKeyboardButton(f"4 | {COEF_GUESS}х", callback_data=f"game_guess_{amount}_4")
        btn_5 = types.InlineKeyboardButton(f"5 | {COEF_GUESS}х", callback_data=f"game_guess_{amount}_5")
        btn_6 = types.InlineKeyboardButton(f"6 | {COEF_GUESS}х", callback_data=f"game_guess_{amount}_6")
        markup.add(btn_1, btn_2)
        markup.add(btn_3, btn_4)
        markup.add(btn_5, btn_6)
        
        bot.edit_message_text(
            f"<blockquote><b>🎮 Выберите игру, на которую хотите сделать ставку</b></blockquote>\n\n"
            f"После оплаты, Ваша ставка сыграет в нашем <a href='{CHANNEL_LINK}'>канале</a>",
            call.message.chat.id,
            call.message.message_id,
            parse_mode='HTML',
            reply_markup=markup,
            disable_web_page_preview=True
        )

    @bot.callback_query_handler(func=lambda call: call.data.startswith("winter_"))
    def winter_choice(call):
        amount = int(call.data.split("_")[1])
        markup = types.InlineKeyboardMarkup(row_width=2)
        btn_rain = types.InlineKeyboardButton(f"Дождь | {COEF_RAIN}х", callback_data=f"game_rain_{amount}")
        btn_snow = types.InlineKeyboardButton(f"Снег | {COEF_SNOW}х", callback_data=f"game_snow_{amount}")
        markup.add(btn_rain, btn_snow)
        
        bot.edit_message_text(
            f"<blockquote><b>🎮 Выберите игру, на которую хотите сделать ставку</b></blockquote>\n\n"
            f"После оплаты, Ваша ставка сыграет в нашем <a href='{CHANNEL_LINK}'>канале</a>",
            call.message.chat.id,
            call.message.message_id,
            parse_mode='HTML',
            reply_markup=markup,
            disable_web_page_preview=True
        )

    @bot.callback_query_handler(func=lambda call: call.data.startswith("game_"))
    def game_choice(call):
        parts = call.data.split("_")
        game_type = parts[1]
        amount = int(parts[2])
        outcome = parts[3] if len(parts) > 3 else None
        
        markup = types.InlineKeyboardMarkup()
        btn_yes = types.InlineKeyboardButton("Да", callback_data=f"confirm_{game_type}_{amount}_{outcome}" if outcome else f"confirm_{game_type}_{amount}")
        btn_no = types.InlineKeyboardButton("Нет", callback_data="cancel")
        markup.add(btn_yes, btn_no)
        
        bot.edit_message_text(
            "<b>Вы точно хотите поставить ставку?</b>",
            call.message.chat.id,
            call.message.message_id,
            parse_mode='HTML',
            reply_markup=markup,
            disable_web_page_preview=True
        )

    def get_game_text(game_type, outcome=None):
        if game_type == "more": return "Больше"
        elif game_type == "less": return "Меньше"
        elif game_type == "even": return "Чёт"
        elif game_type == "odd": return "Нечёт"
        elif game_type == "guess" and outcome: return f"Число {outcome}"
        elif game_type == "rain": return "Дождь"
        elif game_type == "snow": return "Снег"
        return ""

    @bot.callback_query_handler(func=lambda call: call.data.startswith("confirm_"))
    def confirm_game(call):
        user_id = call.from_user.id
        parts = call.data.split("_")
        game_type = parts[1]
        amount = int(parts[2])
        outcome = parts[3] if len(parts) > 3 else None
        
        username = call.from_user.username or "NoUsername"
        user_data = db.get(User.user_id == user_id)
        
        new_balance = user_data['balance'] - amount
        new_bets_count = user_data['bets_count'] + 1
        db.update({'balance': new_balance, 'bets_count': new_bets_count}, User.user_id == user_id)
        bets_db.insert({'user_id': user_id, 'amount': amount, 'timestamp': datetime.now().strftime("%Y-%m-%d %H:%M:%S")})
        
        game_text = get_game_text(game_type, outcome)
        coefficient = COEF_GUESS if game_type == "guess" else COEF_RAIN if game_type == "rain" else COEF_SNOW if game_type == "snow" else 2
        potential_win = amount * coefficient
        
        bot.edit_message_text(
            f"<b>Канал со ставками - <a href='{CHANNEL_LINK}'>тык</a></b>",
            call.message.chat.id,
            call.message.message_id,
            parse_mode='HTML',
            disable_web_page_preview=True
        )
        
        channel_msg = bot.send_message(
            CHANNEL_ID,
            f"<b>❤️‍🔥 {user_data['first_name']} {user_data['last_name']} ставит {amount} звёзд на {game_text}</b>\n\n"
            f"<blockquote><b>Коэффициент {coefficient}х</b></blockquote>\n"
            f"<blockquote><b>Предполагаемый выигрыш {potential_win} звёзд</b></blockquote>",
            parse_mode='HTML',
            disable_web_page_preview=True
        )
        
        time.sleep(1)
        if game_type in ["rain", "snow"]:
            chance = SNOW_CHANCE_IF_CHOSEN if game_type == "snow" else RAIN_CHANCE_IF_CHOSEN
            result = "❄️" if (game_type == "snow" and random.randint(1, 100) <= chance) or (game_type == "rain" and random.randint(1, 100) > (100 - chance)) else "⛈"
            dice_msg = bot.send_message(CHANNEL_ID, result, disable_web_page_preview=True)
            dice_value = 1 if result == "❄️" else 0
        else:
            dice = bot.send_dice(CHANNEL_ID)
            dice_value = dice.dice.value
        
        time.sleep(3)
        
        markup = types.InlineKeyboardMarkup()
        bet_button = types.InlineKeyboardButton("🚀 Сделать ставку", url=f"https://t.me/{BOT_USERNAME}?start=bet")
        markup.add(bet_button)
        
        win = check_win(game_type, outcome, dice_value)
        win_multiplier = COEF_GUESS if game_type == "guess" else COEF_RAIN if game_type == "rain" else COEF_SNOW if game_type == "snow" else 2
        
        if win:
            win_amount = amount * win_multiplier
            new_balance = user_data['balance'] - amount + win_amount
            new_total_earned = user_data['total_earned'] + win_amount
            db.update({
                'balance': new_balance,
                'total_earned': new_total_earned
            }, User.user_id == user_id)
            
            if user_data['referred_by']:
                referrer = db.get(User.user_id == user_data['referred_by'])
                ref_bonus = int(win_amount * 0.05)
                ref_balance = referrer['balance'] + ref_bonus
                db.update({'balance': ref_balance}, User.user_id == referrer['user_id'])
                bot.send_message(referrer['user_id'], f"<b>Ваш реферал выиграл {win_amount} звёзд! Вы получили бонус: {ref_bonus} звёзд</b>", parse_mode='HTML', disable_web_page_preview=True)
            
            bot.send_message(
                CHANNEL_ID,
                f"<b>🔥 Победа! Выпало значение {dice_value if game_type not in ['rain', 'snow'] else result}</b>\n\n"
                f"<blockquote><b>На ваш баланс был зачислен выигрыш {win_amount} звёзд.\n"
                f"Опробуйте свою удачу сполна и познайте путь истинных победителей по жизни!</b></blockquote>",
                parse_mode='HTML',
                reply_markup=markup,
                disable_web_page_preview=True
            )
            bot.send_message(
                user_id,
                f"<b>🔥 Победа! Выпало значение {dice_value if game_type not in ['rain', 'snow'] else result}</b>\n\n"
                f"<blockquote><b>На ваш баланс был зачислен выигрыш {win_amount} звёзд.\n"
                f"Опробуйте свою удачу сполна и познайте путь истинных победителей по жизни!</b></blockquote>",
                parse_mode='HTML',
                reply_markup=markup,
                disable_web_page_preview=True
            )
        else:
            bot.send_message(
                CHANNEL_ID,
                f"<b>🚫 Вы проиграли. Попробуйте снова!</b>\n\n"
                f"Выпало значение {dice_value if game_type not in ['rain', 'snow'] else result}",
                parse_mode='HTML',
                reply_markup=markup,
                disable_web_page_preview=True
            )
            bot.send_message(
                user_id,
                f"<b>🚫 Вы проиграли. Попробуйте снова!</b>\n\n"
                f"Выпало значение {dice_value if game_type not in ['rain', 'snow'] else result}",
                parse_mode='HTML',
                reply_markup=markup,
                disable_web_page_preview=True
            )
        
        if not bet_queue.empty():
            process_queue()

    def check_win(game_type, outcome, dice_value):
        if game_type == "more": return dice_value in [4, 5, 6]
        elif game_type == "less": return dice_value in [1, 2, 3]
        elif game_type == "even": return dice_value % 2 == 0
        elif game_type == "odd": return dice_value % 2 != 0
        elif game_type == "guess": return dice_value == int(outcome)
        elif game_type == "rain": return dice_value == 0
        elif game_type == "snow": return dice_value == 1
        return False

    @bot.callback_query_handler(func=lambda call: call.data == "cancel")
    def cancel_game(call):
        bot.edit_message_text(
            "<b>Ставка отменена</b>",
            call.message.chat.id,
            call.message.message_id,
            parse_mode='HTML',
            disable_web_page_preview=True
        )

    @bot.message_handler(func=lambda message: message.text == "⚡️ Профиль")
    def profile_handler(message):
        user_id = message.from_user.id
        user_data = db.get(User.user_id == user_id)
        username = message.from_user.username or "NoUsername"
        
        text = "🎲 <b>Профиль</b>\n"
        text += "➖➖➖➖➖➖➖➖➖➖➖\n"
        text += f"👉🏼 ID: <code>{user_id}</code>\n"
        text += f"💰 Баланс: <code>{user_data['balance']} звёзд</code>\n"
        text += f"⚙ Никнейм: <code>{user_data['first_name']} {user_data['last_name']}</code>\n"
        text += f"🎮 Юзернейм: <code>@{username}</code>\n"
        text += "➖➖➖➖➖➖➖➖➖➖➖\n\n"
        text += "📊 <b>Статистика:</b>\n"
        text += f"💎 Ставок: <code>{user_data['bets_count']}</code>\n"
        text += f"💸 Заработано: <code>{user_data['total_earned']} звёзд</code>\n"
        text += f"📆 Регистрация: <code>{user_data['reg_date']}</code>\n"
        text += "➖➖➖➖➖➖➖➖➖➖➖"
        
        bot.send_message(message.chat.id, text, parse_mode='HTML', disable_web_page_preview=True)

    @bot.message_handler(func=lambda message: message.text == "💳 Пополнить баланс")
    def add_stars_handler(message):
        bot.send_message(message.chat.id,
                        "<b>Введите сколько хотите звезд пополнить на баланс</b>",
                        parse_mode='HTML',
                        disable_web_page_preview=True)
        bot.register_next_step_handler(message, process_payment_amount)

    def process_payment_amount(message):
        try:
            user_id = message.from_user.id
            amount = int(message.text)
            if amount <= 0:
                bot.send_message(message.chat.id, "<b>Введите положительное число</b>", parse_mode='HTML', disable_web_page_preview=True)
                return
            bot.send_invoice(
                message.chat.id,
                "Пополнение звёзд",
                f"Пополнение на {amount} звёзд. Максимум 100.000 звезд",
                f"payment_{user_id}_{amount}",
                "",
                "XTR",
                [types.LabeledPrice(label="Stars", amount=amount)]
            )
        except ValueError:
            bot.send_message(message.chat.id, "<b>Введите число</b>", parse_mode='HTML', disable_web_page_preview=True)

    @bot.pre_checkout_query_handler(func=lambda query: True)
    def process_pre_checkout_query(pre_checkout_query):
        bot.answer_pre_checkout_query(pre_checkout_query.id, ok=True)

    @bot.message_handler(content_types=['successful_payment'])
    def process_successful_payment(message):
        user_id = message.from_user.id
        amount = message.successful_payment.total_amount
        user_data = db.get(User.user_id == user_id)
        new_balance = user_data['balance'] + amount
        db.update({'balance': new_balance}, User.user_id == user_id)
        payments_db.insert({'user_id': user_id, 'amount': amount, 'timestamp': datetime.now().strftime("%Y-%m-%d %H:%M:%S")})
        bot.send_message(message.chat.id, f"<b>✅ Счёт успешно оплачен.\n\n💰 На баланс зачислено {amount} звёзд.</b>", parse_mode='HTML', disable_web_page_preview=True)

    @bot.message_handler(func=lambda message: message.text == "🔗 Реф. система")
    def ref_system(message):
        user_id = message.from_user.id
        user_data = db.get(User.user_id == user_id)
        ref_link = f"https://t.me/{BOT_USERNAME}?start={user_data['ref_code']}"
        bot.send_message(message.chat.id,
                        f"<b>❤️‍🔥 Наша реферальная система:</b>\n\n"
                        f"┏ 🎉 Приглашено рефералов: <code>{user_data['referrals']}</code>\n"
                        f"┣ 💰 Ваш баланс: <code>{user_data['balance']} звёзд</code>\n"
                        f"┣ 💸 Заработано всего: <code>{user_data['total_earned']} звёзд</code>\n"
                        f"┗ 🚀 Ссылка: <code>{ref_link}</code>\n\n"
                        f"💳 Мы платим <b>10%</b> с выигрышей рефералов",
                        parse_mode='HTML',
                        disable_web_page_preview=True)

    @bot.message_handler(func=lambda message: message.text == "🎲 Играть")
    def play_game(message):
        user_id = message.from_user.id
        user_data = db.get(User.user_id == user_id)
        bot.send_message(message.chat.id,
                        f"<b>Пришлите сумму звёзд для оплаты ставки.</b>\n\n"
                        f"Баланс: <code>{user_data['balance']} звёзд</code>",
                        parse_mode='HTML',
                        disable_web_page_preview=True)
        bot.register_next_step_handler(message, process_bet_amount)

    @bot.message_handler(func=lambda message: message.text == "🏆 Топ")
    def top_users(message):
        top_users = sorted([u for u in db.all() if u['user_id'] != ADMIN_ID], key=lambda x: x['total_earned'], reverse=True)[:5]
        text = "<b>💸 Топ 5 пользователей по обороту:</b>\n\n"
        for i, user in enumerate(top_users, 1):
            text += f"{i}. {user['first_name']} {user['last_name']} — <code>{user['total_earned']} ⭐️</code>\n"
        bot.send_message(message.chat.id, text, parse_mode='HTML', disable_web_page_preview=True)

    return bot

def run_bot():
    global BOT_USERNAME  
    while True:
        try:
            bot = create_bot()
            bot.polling(none_stop=True, timeout=60)
        except Exception as e:
            print(f"Произошла ошибка: {str(e)}")
            print("Перезапуск бота")

if __name__ == "__main__":
    run_bot()
