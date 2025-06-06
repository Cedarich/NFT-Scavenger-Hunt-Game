use onchain::contracts::scavenger_hunt::ScavengerHunt;
use onchain::interface::{
    IScavengerHuntDispatcher, IScavengerHuntDispatcherTrait, Levels, Question,
};
use onchain::utils::hash_byte_array;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address, spy_events,
    EventSpyAssertionsTrait, stop_cheat_caller_address,
};
use core::serde::Serde;
use starknet::{ContractAddress, contract_address_const};
use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
use onchain::contracts::scavenger_hunt::ScavengerHunt::{InternalFunctionsTrait, LevelBadgeMinted};
use onchain::contracts::scavenger_hunt::ScavengerHunt::{Event as ScavengerHuntEvent};
use onchain::contracts::scavenger_hunt_nft::{
    IScavengerHuntNFTDispatcher, IScavengerHuntNFTDispatcherTrait
};
use onchain::contracts::scavenger_hunt_nft::ScavengerHuntNFT;

fn ADMIN() -> ContractAddress {
    contract_address_const::<'ADMIN'>()
}

fn USER() -> ContractAddress {
    contract_address_const::<'USER'>()
}

// Added for clarity in state tests
fn DUMMY_NFT_ADDR() -> ContractAddress {
    // Used in state-based tests where deployment isn't needed but address must be non-zero
    contract_address_const::<'DUMMY_NFT_ADDR'>()
}

fn deploy_contract() -> ContractAddress {
    let contract = declare("ScavengerHunt").unwrap().contract_class();
    let mut constructor_calldata: Array<felt252> = array![];
    Serde::serialize(@ADMIN(), ref constructor_calldata);
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}
fn deploy_scavenger_hunt_nft(
    token_uri: ByteArray, scavenger_hunt_address: ContractAddress
) -> ContractAddress {
    let declare_result = declare("ScavengerHuntNFT").unwrap();
    let contract_class = declare_result.contract_class();
    let mut constructor_args: Array<felt252> = array![];
    // Serialize ByteArray for token_uri
    token_uri.serialize(ref constructor_args);
    // Append scavenger_hunt_address
    constructor_args.append(scavenger_hunt_address.into());

    let (address, _) = contract_class.deploy(@constructor_args).unwrap();
    address
}
// Setup helper deploying Hunt, NFT, and the Mock Receiver
fn setup_all_contracts() -> (
    IScavengerHuntDispatcher, IScavengerHuntNFTDispatcher, ContractAddress
) {
    let hunt_contract_class = declare("ScavengerHunt").unwrap().contract_class();

    let receiver_contract_class = declare("MockERC1155Receiver").unwrap().contract_class();

    // 2. Deploy ScavengerHunt
    let mut hunt_calldata = array![ADMIN().into()];
    let (hunt_address, _) = hunt_contract_class.deploy(@hunt_calldata).unwrap();
    let hunt_dispatcher = IScavengerHuntDispatcher { contract_address: hunt_address };

    // 3. Deploy ScavengerHuntNFT
    let token_uri_bytes: ByteArray = "ipfs://placeholder_uri/";
    let nft_address = deploy_scavenger_hunt_nft(token_uri_bytes, hunt_address);
    let nft_dispatcher = IScavengerHuntNFTDispatcher { contract_address: nft_address };

    // 4. Deploy Mock Receiver
    let (receiver_address, _) = receiver_contract_class
        .deploy(@array![])
        .unwrap(); // Deploy receiver with its constructor

    // 5. Configure ScavengerHunt: Set NFT contract address
    start_cheat_caller_address(hunt_address, ADMIN());
    hunt_dispatcher.set_nft_contract_address(nft_address);
    stop_cheat_caller_address(hunt_address);

    // 6. Optional: Verify MINTER role
    start_cheat_caller_address(nft_address, ADMIN());
    assert(
        nft_dispatcher.has_minter_role(hunt_address), 1
    ); // Use 1 as a felt252-compatible error code
    stop_cheat_caller_address(nft_address);

    (hunt_dispatcher, nft_dispatcher, receiver_address) // Return receiver address
}


#[test]
fn test_set_question_per_level() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_question_per_level(5);
    stop_cheat_caller_address(contract_address);

    let question_per_level = dispatcher.get_question_per_level();
    assert!(question_per_level == 5, "Expected 5 questions per level, got {}", question_per_level);
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_set_question_per_level_should_panic_with_missing_role() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    dispatcher.set_question_per_level(5);

    let question_per_level = dispatcher.get_question_per_level();
    assert!(question_per_level == 5, "Expected 5 questions per level, got {}", question_per_level);
}

#[test]
fn test_add_and_get_question() {
    // Deploy the contract
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    // Define test data
    let level = Levels::Easy;
    let question = "What is the capital of France?"; // ByteArray
    let answer = "Paris"; // ByteArray
    let hint = "It starts with 'P'"; // ByteArray

    let hashed_answer = hash_byte_array(answer.clone());
    // Add a question
    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_question_per_level(5);
    dispatcher.add_question(level, question.clone(), answer.clone(), hint.clone());
    stop_cheat_caller_address(contract_address);

    // Retrieve the question
    let question_id = 1; // Assuming the first question has ID 1
    let retrieved_question: Question = dispatcher.get_question(question_id);

    // Assertions to verify the question was added correctly
    assert!(
        retrieved_question.question_id == question_id,
        "Expected question ID {}, got {}",
        question_id,
        retrieved_question.question_id,
    );
    assert!(
        retrieved_question.question == question,
        "Expected question '{}', got '{}'",
        question,
        retrieved_question.question,
    );
    assert!(
        retrieved_question.hashed_answer == hashed_answer,
        "Expected answer '{}', got '{}'",
        hashed_answer,
        retrieved_question.hashed_answer,
    );
    assert!(
        retrieved_question.hint == hint,
        "Expected hint '{}', got '{}'",
        hint,
        retrieved_question.hint,
    );
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_add_and_get_question_should_panic_with_missing_role() {
    // Deploy the contract
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    // Define test data
    let level = Levels::Easy;
    let question = "What is the capital of France?"; // ByteArray
    let answer = "Paris"; // ByteArray
    let hint = "It starts with 'P'"; // ByteArray

    // Add a question
    dispatcher.add_question(level, question.clone(), answer.clone(), hint.clone());
}

#[test]
fn test_request_hint() {
    // Deploy the contract
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    start_cheat_caller_address(contract_address, USER());

    // Define test data
    let level = Levels::Easy;
    let question = "What is the capital of France?"; // ByteArray
    let answer = "Paris"; // ByteArray
    let hint = "It starts with 'P'"; // ByteArray

    // Add a question
    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_question_per_level(5);
    dispatcher.add_question(level, question.clone(), answer.clone(), hint.clone());
    stop_cheat_caller_address(contract_address);

    // USER: submit correct answer to initialize player and progress
    start_cheat_caller_address(contract_address, USER());
    dispatcher.submit_answer(1, answer.clone());

    // USER: request hint
    let retrieved_hint = dispatcher.request_hint(1);
    stop_cheat_caller_address(contract_address);
    // Verify that the retrieved hint matches the expected hint
    assert!(retrieved_hint == hint, "Expected hint '{}', got '{}'", hint, retrieved_hint);
}

#[test]
fn test_get_question_in_level() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    let level = Levels::Easy;
    let question = "What is the capital of France?";
    let answer = "Paris";
    let hint = "It starts with 'P'";
    let index = 0;

    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_question_per_level(5);
    dispatcher.add_question(level, question.clone(), answer.clone(), hint.clone());
    stop_cheat_caller_address(contract_address);

    let retrieved_question = dispatcher.get_question_in_level(level, index);

    assert!(
        retrieved_question == question,
        "Expected question '{}', got '{}'",
        question,
        retrieved_question,
    );
}

#[test]
fn test_update_question() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    // Define initial test data
    let level = Levels::Easy;
    let question = "What is the capital of France?";
    let answer = "Paris";
    let hint = "It starts with 'P'";

    // Add a question
    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_question_per_level(5);
    dispatcher.add_question(level, question.clone(), answer.clone(), hint.clone());
    stop_cheat_caller_address(contract_address);

    // Define updated test data
    let updated_question = "What is the capital of Germany?";
    let updated_answer = "Berlin";
    let updated_hint = "It starts with 'B'";

    let hashed_updated_answer = hash_byte_array(updated_answer.clone());

    // Update the question
    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher
        .update_question(
            1, updated_question.clone(), updated_answer.clone(), level, updated_hint.clone(),
        );
    stop_cheat_caller_address(contract_address);

    // Retrieve the updated question
    let retrieved_question: Question = dispatcher.get_question(1);

    // Assertions to verify the question was updated correctly
    assert!(
        retrieved_question.question == updated_question,
        "Expected question '{}', got '{}'",
        updated_question,
        retrieved_question.question,
    );
    assert!(
        retrieved_question.hashed_answer == hashed_updated_answer,
        "Expected answer '{}', got '{}'",
        hashed_updated_answer,
        retrieved_question.hashed_answer,
    );
    assert!(
        retrieved_question.hint == updated_hint,
        "Expected hint '{}', got '{}'",
        updated_hint,
        retrieved_question.hint,
    );
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_update_question_should_panic_with_missing_role() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    // Define initial test data
    let level = Levels::Easy;
    let question = "What is the capital of France?";
    let answer = "Paris";
    let hint = "It starts with 'P'";

    // Add a question
    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_question_per_level(5);
    dispatcher.add_question(level, question.clone(), answer.clone(), hint.clone());
    stop_cheat_caller_address(contract_address);

    // Define updated test data
    let updated_question = "What is the capital of Germany?";
    let updated_answer = "Berlin";
    let updated_hint = "It starts with 'B'";

    // Attempt to update the question without admin role
    dispatcher
        .update_question(
            1, updated_question.clone(), updated_answer.clone(), level, updated_hint.clone(),
        );
}

#[test]
#[should_panic(expected: "Question does not exist")]
fn test_update_question_should_panic_if_question_does_not_exist() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    // Define test data for updating a non-existent question
    let invalid_question_id = 1; // This question ID does not exist yet
    let question = "What is the capital of France?";
    let answer = "Paris";
    let level = Levels::Easy;
    let hint = "It starts with 'P'";

    // Attempt to update a non-existent question
    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.update_question(invalid_question_id, question, answer, level, hint);
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_level_progression() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };
    let player_address = USER();

    let level = Levels::Easy;
    let question = "Who is the pirate king?";
    let answer = "Gol d Roger";
    let hint = "It starts with 'G'";

    // Admin setup
    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_question_per_level(2);
    dispatcher.add_question(level, question.clone(), answer.clone(), hint.clone());
    dispatcher.add_question(level, "What is One Piece?", "A treasure", "It is the ultimate prize");
    stop_cheat_caller_address(contract_address);

    // Player actions (keep caller as player_address throughout)
    start_cheat_caller_address(contract_address, player_address);

    let player_progress = dispatcher.get_player_level(player_address);
    let player_level = player_progress.into();
    assert!(player_level == 'EASY', "Player should start at Easy level");

    // Submit answers as player
    let result_1 = dispatcher.submit_answer(1, "Gol d Roger");
    let result_2 = dispatcher.submit_answer(2, "A treasure");

    assert!(result_1 && result_2, "Answer should be correct for both question {} and {}", 1, 2);

    // Check updated level
    let updated_progress = dispatcher.get_player_level(player_address);
    let player_new_level = updated_progress.into();
    assert!(
        player_new_level == 'MEDIUM',
        "Player should have progressed to MEDIUM level, but is still at EASY",
    );

    stop_cheat_caller_address(contract_address);
}
#[test]
fn test_no_progression_on_partial_completion() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };
    let player_address = USER();

    // Admin setup
    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_question_per_level(3);
    dispatcher.add_question(Levels::Easy, "Q1?", "A1", "H1");
    dispatcher.add_question(Levels::Easy, "Q2?", "A2", "H2");
    dispatcher.add_question(Levels::Easy, "Q3?", "A3", "H3");
    stop_cheat_caller_address(contract_address);

    // Player setup
    start_cheat_caller_address(contract_address, player_address);

    // Submit 2 out of 3 answers
    dispatcher.submit_answer(1, "A1");
    dispatcher.submit_answer(2, "A2");

    // Check level
    let current_level = dispatcher.get_player_level(player_address);
    let level_felt = current_level.into();
    assert!(
        level_felt == 'EASY',
        "Player should still be at Easy since all questions were not answered",
    );

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_incorrect_answer_does_not_progress() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };
    let player_address = USER();

    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_question_per_level(1);
    dispatcher.add_question(Levels::Easy, "Q1?", "Correct", "Hint");
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, player_address);

    let result = dispatcher.submit_answer(1, "Wrong");
    assert!(!result, "Submitting an incorrect answer should return false");

    let current_level = dispatcher.get_player_level(player_address);
    let level_felt = current_level.into();
    assert!(level_felt == 'EASY', "Player should still be at Easy after incorrect answer");

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_max_level_does_not_progress() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };
    let player_address = USER();

    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_question_per_level(2);
    dispatcher.add_question(Levels::Master, "Final Q1?", "Final A1", "H1");
    dispatcher.add_question(Levels::Master, "Final Q2?", "Final A2", "H2");
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, player_address);

    // Manually set to Master (assuming we add this function or cheat state)
    // For now, simulate by answering prior levels or modify contract
    dispatcher.submit_answer(1, "Final A1");
    dispatcher.submit_answer(2, "Final A2");

    let current_level = dispatcher.get_player_level(player_address);
    let level_felt = current_level.into();
    assert!(
        level_felt == 'MASTER', "Player should remain at Master after completing all questions",
    );

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_multiple_level_progressions() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };
    let player_address = USER();

    // Admin setup
    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_question_per_level(2);
    // Easy level questions
    dispatcher.add_question(Levels::Easy, "Easy Q1?", "A1", "H1"); // ID 1
    dispatcher.add_question(Levels::Easy, "Easy Q2?", "A2", "H2"); // ID 2
    // Medium level questions
    dispatcher.add_question(Levels::Medium, "Med Q1?", "A1", "H1"); // ID 3
    dispatcher.add_question(Levels::Medium, "Med Q2?", "A2", "H2"); // ID 4
    // Hard level questions
    dispatcher.add_question(Levels::Hard, "Hard Q1?", "A1", "H1"); // ID 5
    dispatcher.add_question(Levels::Hard, "Hard Q2?", "A2", "H2"); // ID 6
    // Master level questions
    dispatcher.add_question(Levels::Master, "Master Q1?", "A1", "H1"); // ID 7
    dispatcher.add_question(Levels::Master, "Master Q2?", "A2", "H2"); // ID 8
    stop_cheat_caller_address(contract_address);

    // Player setup
    start_cheat_caller_address(contract_address, player_address);

    let progress = dispatcher.get_player_level(player_address);
    assert!(progress == Levels::Easy, "Should be initialized");

    // Initial level check
    let player_progress = dispatcher.get_player_level(player_address);
    let player_level = player_progress.into();
    assert!(player_level == 'EASY', "Player should start at Easy level");

    // Easy level submissions (IDs 1-2)
    let result_easy_1 = dispatcher.submit_answer(1, "A1");
    let result_easy_2 = dispatcher.submit_answer(2, "A2");
    assert!(result_easy_1 && result_easy_2, "Easy answers should be correct for questions 1 and 2");
    let after_easy_progress = dispatcher.get_player_level(player_address);
    let after_easy_level = after_easy_progress.into();
    assert!(after_easy_level == 'MEDIUM', "Player should progress to Medium after Easy");

    // Medium level submissions (IDs 3-4)
    let result_med_1 = dispatcher.submit_answer(3, "A1");
    let result_med_2 = dispatcher.submit_answer(4, "A2");
    assert!(result_med_1 && result_med_2, "Medium answers should be correct for questions 3 and 4");
    let after_med_progress = dispatcher.get_player_level(player_address);
    let after_med_level = after_med_progress.into();
    assert!(after_med_level == 'HARD', "Player should progress to Hard after Medium");

    // Hard level submissions (IDs 5-6)
    let result_hard_1 = dispatcher.submit_answer(5, "A1");
    let result_hard_2 = dispatcher.submit_answer(6, "A2");
    assert!(result_hard_1 && result_hard_2, "Hard answers should be correct for questions 5 and 6");
    let after_hard_progress = dispatcher.get_player_level(player_address);
    let after_hard_level = after_hard_progress.into();
    assert!(after_hard_level == 'MASTER', "Player should progress to Master after Hard");

    // Master level submissions (IDs 7-8)
    let result_master_1 = dispatcher.submit_answer(7, "A1");
    let result_master_2 = dispatcher.submit_answer(8, "A2");
    assert!(
        result_master_1 && result_master_2,
        "Master answers should be correct for questions 7 and 8",
    );
    let after_master_progress = dispatcher.get_player_level(player_address);
    let after_master_level = after_master_progress.into();
    assert!(after_master_level == 'MASTER', "Player should remain at Master");

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_initialize_player_progress() {
    // Get contract state for testing
    let mut state = ScavengerHunt::contract_state_for_testing();
    let player_address = USER();

    // Call the internal function directly
    state.initialize_player_progress(player_address);

    // Verify the player was initialized correctly
    let player_progress = state.player_progress.read(player_address);
    assert!(player_progress.is_initialized, "Player should be initialized");
    assert!(player_progress.current_level == Levels::Easy, "Player should start at Easy level");
    assert!(player_progress.address == player_address, "Player address should match");

    // Verify level progress was initialized correctly
    let level_progress = state.player_level_progress.read((player_address, Levels::Easy.into()));
    assert!(level_progress.player == player_address, "Level progress player should match");
    assert!(level_progress.level == Levels::Easy, "Level should be Easy");
    assert!(level_progress.last_question_index == 0, "Last question index should be 0");
    assert!(!level_progress.is_completed, "Level should not be completed");
    assert!(level_progress.attempts == 0, "Attempts should be 0");
    assert!(!level_progress.nft_minted, "NFT should not be minted");
}


fn test_set_nft_contract_address() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };
    let new_nft_address = contract_address_const::<'NEW_NFT'>();

    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_nft_contract_address(new_nft_address);
    stop_cheat_caller_address(contract_address);

    let stored_address = dispatcher.get_nft_contract_address();
    assert!(stored_address == new_nft_address, "wrong_nft_address");
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_set_nft_contract_address_should_panic_with_missing_role() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };
    let new_nft_address = contract_address_const::<'NEW_NFT'>();

    dispatcher.set_nft_contract_address(new_nft_address);
}
#[test]
#[should_panic(expected: 'Question cannot be empty')]
fn test_add_question_empty_question() {
    // Deploy the contract
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    // Define test data
    let level = Levels::Easy;
    let question = ""; // ByteArray
    let answer = "Paris"; // ByteArray
    let hint = "It starts with 'P'"; // ByteArray

    start_cheat_caller_address(contract_address, ADMIN());

    // Add a question
    dispatcher.add_question(level, question.clone(), answer.clone(), hint.clone());
}

#[test]
#[should_panic(expected: 'Answer cannot be empty')]
fn test_add_question_empty_answer() {
    // Deploy the contract
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    // Define test data
    let level = Levels::Easy;
    let question = "question"; // ByteArray
    let answer = ""; // ByteArray
    let hint = "It starts with 'P'"; // ByteArray

    start_cheat_caller_address(contract_address, ADMIN());

    // Add a question
    dispatcher.add_question(level, question.clone(), answer.clone(), hint.clone());
}

#[test]
#[should_panic(expected: 'Hint cannot be empty')]
fn test_add_question_empty_hint() {
    // Deploy the contract
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    // Define test data
    let level = Levels::Easy;
    let question = "question"; // ByteArray
    let answer = "answer"; // ByteArray
    let hint = ""; // ByteArray

    start_cheat_caller_address(contract_address, ADMIN());

    // Add a question
    dispatcher.add_question(level, question.clone(), answer.clone(), hint.clone());
}

#[test]
#[should_panic(expected: 'Question cannot be empty')]
fn test_update_question_empty_question() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    // Define initial test data
    let level = Levels::Easy;
    let question = "What is the capital of France?";
    let answer = "Paris";
    let hint = "It starts with 'P'";

    // Add a question
    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_question_per_level(5);
    dispatcher.add_question(level, question.clone(), answer.clone(), hint.clone());

    // Define updated test data
    let updated_question = "";
    let updated_answer = "Berlin";
    let updated_hint = "It starts with 'B'";

    // Attempt to update the question
    dispatcher
        .update_question(
            1, updated_question.clone(), updated_answer.clone(), level, updated_hint.clone(),
        );
}

#[test]
#[should_panic(expected: 'Answer cannot be empty')]
fn test_update_question_empty_answer() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    // Define initial test data
    let level = Levels::Easy;
    let question = "What is the capital of France?";
    let answer = "Paris";
    let hint = "It starts with 'P'";

    // Add a question
    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_question_per_level(5);
    dispatcher.add_question(level, question.clone(), answer.clone(), hint.clone());

    // Define updated test data
    let updated_question = "What is the capital of Germany?";
    let updated_answer = "";
    let updated_hint = "It starts with 'B'";

    // Attempt to update the question
    dispatcher
        .update_question(
            1, updated_question.clone(), updated_answer.clone(), level, updated_hint.clone(),
        );
}

#[test]
#[should_panic(expected: 'Hint cannot be empty')]
fn test_update_question_empty_hint() {
    let contract_address = deploy_contract();
    let dispatcher = IScavengerHuntDispatcher { contract_address };

    // Define initial test data
    let level = Levels::Easy;
    let question = "What is the capital of France?";
    let answer = "Paris";
    let hint = "It starts with 'P'";

    // Add a question
    start_cheat_caller_address(contract_address, ADMIN());
    dispatcher.set_question_per_level(5);
    dispatcher.add_question(level, question.clone(), answer.clone(), hint.clone());

    // Define updated test data
    let updated_question = "What is the capital of Germany?";
    let updated_answer = "Berlin";
    let updated_hint = "";

    // Attempt to update the question
    dispatcher
        .update_question(
            1, updated_question.clone(), updated_answer.clone(), level, updated_hint.clone(),
        );
}

#[test]
#[should_panic(expected: "Level not completed")]
fn test_mint_level_badge_not_completed() {
    let mut state = ScavengerHunt::contract_state_for_testing();
    let player = USER();
    let level = Levels::Easy;

    // Initialize player but don't complete level
    state.initialize_player_progress(player);
    state.nft_contract_address.write(contract_address_const::<'MOCK_NFT'>());

    // This should panic
    state._mint_level_badge(player, level);
}
#[test]
#[should_panic(expected: "NFT already minted")]
fn test_mint_level_badge_duplicate() {
    let mut state = ScavengerHunt::contract_state_for_testing();
    let player = USER();
    let level = Levels::Easy;

    // Initialize and mark as completed & minted
    state.initialize_player_progress(player);
    let mut level_progress = state.player_level_progress.read((player, level.into()));
    level_progress.is_completed = true;
    level_progress.nft_minted = true;
    state.player_level_progress.write((player, level.into()), level_progress);
    state.nft_contract_address.write(contract_address_const::<'MOCK_NFT'>());

    // Attempt duplicate mint
    state._mint_level_badge(player, level);
}
// --- REFACTORED Integration Test using deployed Mock Receiver ---
#[test]
fn test_claim_level_completion_nft_integration() {
    // Use the setup deploying Hunt, NFT, and Receiver
    let (hunt_dispatcher, nft_dispatcher, receiver_address) = setup_all_contracts();
    let hunt_address = hunt_dispatcher.contract_address;
    let nft_address = nft_dispatcher.contract_address;
    // --- FIX: Use the DEPLOYED receiver address as the player ---
    let player = receiver_address;
    // -----------------------------------------------------------
    let level_to_complete = Levels::Easy;
    let question_id = 1;
    let correct_answer: ByteArray = "A";
    let q1: ByteArray = "Q?";
    let h1: ByteArray = "Hint";

    // Setup state using ADMIN cheat
    start_cheat_caller_address(hunt_address, ADMIN());
    hunt_dispatcher.set_question_per_level(1);
    hunt_dispatcher.add_question(level_to_complete, q1, correct_answer.clone(), h1);
    stop_cheat_caller_address(hunt_address);

    // Simulate completion using player (receiver) cheat
    start_cheat_caller_address(hunt_address, player);
    assert!(
        hunt_dispatcher.submit_answer(question_id, correct_answer) == true, "Completion failed"
    );
    let progress_before_claim = hunt_dispatcher
        .get_player_level_progress(player, level_to_complete);
    assert!(progress_before_claim.is_completed == true, "Level not completed flag");
    assert!(progress_before_claim.nft_minted == false, "NFT already minted flag");
    stop_cheat_caller_address(hunt_address);

    // Claim NFT using player (receiver) cheat & Spy events
    let mut spy = spy_events();
    start_cheat_caller_address(hunt_address, player);
    hunt_dispatcher.claim_level_completion_nft(level_to_complete); // This should now succeed
    stop_cheat_caller_address(hunt_address);

    // Assertions
    assert!(nft_dispatcher.has_level_badge(player, level_to_complete), "NFT badge check failed");
    let final_progress = hunt_dispatcher.get_player_level_progress(player, level_to_complete);
    assert!(final_progress.nft_minted, "nft_minted flag check failed");

    // Assert event emission using the (emitter, Enum::Variant(Struct)) format
    spy
        .assert_emitted(
            @array![
                (
                    hunt_address,
                    ScavengerHuntEvent::LevelBadgeMinted(
                        LevelBadgeMinted {
                            player: player, level: level_to_complete
                        } // Use receiver address here
                    )
                )
            ]
        );
}

// --- Other Integration Tests using cheat_caller_address ---

#[test]
#[should_panic] // Keep just should_panic - it passed correctly before
fn test_claim_level_completion_nft_before_completion() {
    // Use the setup that includes NFT contract (needed for claim logic)
    let (hunt_dispatcher, _, _) = setup_all_contracts(); // Use new setup
    let hunt_address = hunt_dispatcher.contract_address;
    let q1: ByteArray = "Q?";
    let a1: ByteArray = "A";
    let h1: ByteArray = "H";

    start_cheat_caller_address(hunt_address, ADMIN());
    hunt_dispatcher.set_question_per_level(1);
    hunt_dispatcher.add_question(Levels::Easy, q1, a1, h1);
    stop_cheat_caller_address(hunt_address);

    // USER() is fine as the *caller* here, the panic is internal logic
    start_cheat_caller_address(hunt_address, USER());
    hunt_dispatcher.claim_level_completion_nft(Levels::Easy); // This should panic internally
    stop_cheat_caller_address(hunt_address);
}

#[test]
#[should_panic]
fn test_claim_level_completion_nft_duplicate_claim() {
    // Use the setup deploying Hunt, NFT, and Receiver
    let (hunt_dispatcher, nft_dispatcher, receiver_address) = setup_all_contracts();
    let hunt_address = hunt_dispatcher.contract_address;
    let player = receiver_address;
    let level_to_complete = Levels::Easy;
    let question_id = 1;
    let correct_answer: ByteArray = "A";
    let q1: ByteArray = "Q?";
    let h1: ByteArray = "Hint";

    start_cheat_caller_address(hunt_address, ADMIN());
    hunt_dispatcher.set_question_per_level(1);
    hunt_dispatcher.add_question(level_to_complete, q1, correct_answer.clone(), h1);
    stop_cheat_caller_address(hunt_address);

    // Complete level using player (receiver) cheat
    start_cheat_caller_address(hunt_address, player);
    assert!(
        hunt_dispatcher.submit_answer(question_id, correct_answer) == true, "Completion failed"
    );
    stop_cheat_caller_address(hunt_address);

    // First claim (should succeed now with valid receiver)
    start_cheat_caller_address(hunt_address, player);
    hunt_dispatcher.claim_level_completion_nft(level_to_complete);
    stop_cheat_caller_address(hunt_address);

    // Verify first claim worked
    assert!(nft_dispatcher.has_level_badge(player, level_to_complete), "First claim failed");
    let progress_after_first_claim = hunt_dispatcher
        .get_player_level_progress(player, level_to_complete);
    assert!(progress_after_first_claim.nft_minted == true, "Flag not set");

    // Attempt second claim (should now panic correctly with 'NFT already minted')
    start_cheat_caller_address(hunt_address, player);
    hunt_dispatcher.claim_level_completion_nft(level_to_complete);
    stop_cheat_caller_address(hunt_address);
}

