/// ChessWager.move
///
/// Simple wager-based chess game contract for Sui testnet.
/// Two players lock equal SUI deposits before playing.
/// Winner claims the pot less a 2% fee sent to the contract owner.
/// Includes randomness helper for AI games using Sui's built-in random object.

module chess_wager::chess_wager {
    use sui::object::{Self, UID};
    // Import helpful modules from Sui. These provide coin types,
    // object identifiers, transfer utilities, and randomness.
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::random;
    /// Different phases a game can be in
    /// Waiting: only player1 joined
    /// InProgress: both players joined
    /// Completed: winner was declared
    /// Cancelled: game was aborted

    /// Game state enum
    public enum GameState: u8 {
        Waiting = 0,
        InProgress = 1,
        Completed = 2,
        Cancelled = 3,
    }

    /// Configuration object storing contract owner
    public struct GameConfig has key {
        /// Unique object ID used for Sui objects
        id: UID,
        /// Address of contract owner to receive fees
        owner: address,
    }

    /// Each active game is stored as an on-chain object
    public struct Game has key {
        /// Unique object ID for this game
        id: UID,
        /// Address of the first player
        player1: address,
        /// Address of the second player
        player2: address,
        /// Amount each player wagered
        wager_amount: u64,
        /// Combined pot holding both wagers
        pot: Coin<SUI>,
        /// Current game state
        state: GameState,
        /// Winner address once decided
        winner: option<address>,
    }

    /// Create the configuration object. Must be called once by deployer
    /// Stores the contract owner so fees can be paid out later.
    public entry fun init(owner: &signer, ctx: &mut TxContext) {
        let config = GameConfig { id: object::new(ctx), owner: signer::address_of(owner) };
        transfer::share_object(config);
    }

    /// Helper to check a coin is exactly the expected amount
    fun assert_amount(coin: &Coin<SUI>, amount: u64) {
        assert!(coin::value(coin) == amount, 0);
    }

    /// Player1 starts a new game by depositing their wager. The game
    /// object is returned so player2 can join later.
    public entry fun create_game(
        player1: &signer,
        player2_addr: address,
        coin1: Coin<SUI>,
        wager_amount: u64,
        ctx: &mut TxContext,
    ): Game {
        assert_amount(&coin1, wager_amount);
        Game {
            id: object::new(ctx),
            player1: signer::address_of(player1),
            player2: player2_addr,
            wager_amount,
            pot: coin1,
            state: GameState::Waiting,
            winner: option::none(),
        }
    }

    /// Player2 joins the game by providing the same wager amount
    public entry fun join_game(
        player2: &signer,
        mut game: Game,
        coin2: Coin<SUI>,
    ): Game {
        assert!(signer::address_of(player2) == game.player2, 1);
        assert!(game.state == GameState::Waiting, 2);
        assert_amount(&coin2, game.wager_amount);
        coin::merge(&mut game.pot, coin2);
        game.state = GameState::InProgress;
        game
    }

    /// Helper for AI logic: returns a random u64 number
    public fun random_u64(ctx: &mut TxContext): u64 {
        let random_obj = borrow_global<random::Random>(@0x8);
        let mut g = random::new_generator(&random_obj, ctx);
        random::generate_u64(&mut g)
    }

    /// Declare the winner and distribute funds
    /// Sends 2% fee to contract owner and the rest to the winner
    public entry fun declare_winner(
        cfg: &GameConfig,
        winner_signer: &signer,
        mut game: Game,
        ctx: &mut TxContext,
    ) {
        assert!(game.state == GameState::InProgress, 3);
        let winner_addr = signer::address_of(winner_signer);
        assert!(winner_addr == game.player1 || winner_addr == game.player2, 4);
        let total = coin::value(&game.pot);
        let fee = total / 50; // 2%
        let reward = total - fee;
        let (fee_coin, reward_coin) = coin::split(game.pot, fee);
        transfer::transfer(reward_coin, winner_addr);
        transfer::transfer(fee_coin, cfg.owner);
        game.state = GameState::Completed;
        game.winner = option::some(winner_addr);
        transfer::delete(game);
    }
    /// Cancel an unstarted game and refund player1
    public entry fun cancel_game(mut game: Game) {
        assert!(game.state == GameState::Waiting, 5);
        transfer::transfer(game.pot, game.player1);
        transfer::delete(game);
    }
}
